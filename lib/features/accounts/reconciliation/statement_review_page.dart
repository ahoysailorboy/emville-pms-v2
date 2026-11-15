import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'reconciliation_repository.dart';

class StatementReviewPage extends StatefulWidget {
  const StatementReviewPage({super.key, required this.id});
  final String id;
  @override
  State<StatementReviewPage> createState() => _StatementReviewPageState();
}

class _StatementReviewPageState extends State<StatementReviewPage> {
  final _repo = BankReconciliationRepository(Supabase.instance.client);
  late Future<Map<String, dynamic>> _data;
  bool _busy = false;
  String _filter = 'Needs review';
  @override
  void initState() {
    super.initState();
    _data = _repo.detail(widget.id);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _data = _repo.detail(widget.id);
    });
    try {
      await _data;
    } catch (_) {}
  }

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _refresh();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not save. Refresh and try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf(String path) async {
    try {
      final url = await _repo.client.storage
          .from('bank-statements')
          .createSignedUrl(path, 120);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the statement PDF.')));
      }
    }
  }

  Future<void> _approve(
      Map<String, dynamic> line, Map<String, dynamic> proposal) async {
    final result = await showDialog<(String, String)>(
        context: context,
        builder: (_) => _ApprovalDialog(line: line, proposal: proposal));
    if (result != null) {
      await _act(() => _repo.approve(proposal['id'], result.$1, result.$2));
    }
  }

  Future<void> _resolve(
      Map<String, dynamic> line, List<Map<String, dynamic>> ledger) async {
    final result = await showDialog<(String, String, String?)>(
        context: context,
        builder: (_) => _ResolutionDialog(line: line, ledger: ledger));
    if (result != null) {
      await _act(() =>
          _repo.resolve(line['id'], result.$1, result.$2, ledger: result.$3));
    }
  }

  Future<void> _ledgerReview(Map<String, dynamic> l) async {
    final result = await showDialog<(String, String, String?)>(
        context: context,
        builder: (_) =>
            _ResolutionDialog(ledgerOnly: true, line: l, ledger: const []));
    if (result != null) {
      await _act(
          () => _repo.reviewLedger(widget.id, l['id'], result.$1, result.$2));
    }
  }

  Future<void> _distinct(Map<String, dynamic> line) async {
    final note = await showDialog<String>(
        context: context,
        builder: (_) => const _NoteDialog(
            title: 'Propose a separate bank entry?',
            description:
                'Use this only after checking that no existing ledger entry represents this transaction. A separate approval will still be required.',
            minimum: 10));
    if (note != null) await _act(() => _repo.proposeDistinct(line['id'], note));
  }

  Future<void> _reversal(Map<String, dynamic> proposal) async {
    final note = await showDialog<String>(
        context: context,
        builder: (_) => _NoteDialog(
            title: 'Approve duplicate reversal?',
            description:
                'Post ${proposal['transaction_type']} ${rupees(proposal['amount'])} to offset the duplicate. The original ledger entry will remain in the audit trail.'));
    if (note != null) {
      await _act(() => _repo.approveReversal(proposal['id'], note));
    }
  }

  Future<void> _discard() async {
    final note = await showDialog<String>(
        context: context,
        builder: (_) => const _NoteDialog(
            title: 'Discard this draft?',
            description:
                'The PDF and review history will be retained, but you can upload a corrected statement for this month. Drafts with posted entries cannot be discarded.'));
    if (note != null) {
      var discarded = false;
      await _act(() async {
        await _repo.discard(widget.id, note);
        discarded = true;
      });
      if (discarded && mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 2,
      child: EmvilleBody(
          child: FutureBuilder(
              future: _data,
              builder: (context, s) {
                if (s.hasError) {
                  return EmvilleError(
                      message:
                          'Could not load this reconciliation. Admin access is required.',
                      onRetry: _refresh);
                }
                if (!s.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = s.data!,
                    session = data['session'] as Map<String, dynamic>;
                final lines = List<Map<String, dynamic>>.from(data['lines']),
                    proposals =
                        List<Map<String, dynamic>>.from(data['proposals']);
                final links = List<Map<String, dynamic>>.from(data['links']),
                    ledger = List<Map<String, dynamic>>.from(data['ledger']),
                    reviews = List<Map<String, dynamic>>.from(data['reviews']);
                final reversals =
                    List<Map<String, dynamic>>.from(data['reversals']);
                final people = List<Map<String, dynamic>>.from(data['people']);
                String actorName(dynamic id) =>
                    people
                        .where((u) => u['uid'] == id)
                        .map((u) => u['full_name'].toString())
                        .firstOrNull ??
                    'Admin';
                final completed = session['status'] == 'completed';
                final month = DateTime.parse(session['month']);
                final pending = lines
                    .where((r) => ![
                          'matched',
                          'timing',
                          'transfer',
                          'duplicate'
                        ].contains(r['state']))
                    .length;
                final used =
                    List<Map<String, dynamic>>.from(data['globalLinks'])
                        .map((l) => l['ledger_id'])
                        .toSet();
                final missingLedger = ledger.where((l) {
                  final date = DateTime.parse(l['date']);
                  return date.year == month.year &&
                      date.month == month.month &&
                      !used.contains(l['id']);
                }).toList();
                final ledgerNet = ledger.where((l) {
                  final d = DateTime.parse(l['date']);
                  return d.year == month.year &&
                      d.month == month.month &&
                      l['transaction_status'] == 'approved';
                }).fold<num>(
                    0,
                    (sum, l) =>
                        sum +
                        (l['transaction_type'] == 'income' ? 1 : -1) *
                            (l['amount'] as num));
                final staleLinks = links
                    .where((k) => ledger.any((l) =>
                        l['id'] == k['ledger_id'] &&
                        !mapEquals(
                            Map<String, dynamic>.from(k['ledger_snapshot']),
                            l)))
                    .length;
                final bankNet = (session['closing_balance'] as num) -
                    (session['opening_balance'] as num);
                final shown = lines
                    .where((r) =>
                        _filter == 'All' ||
                        !['matched', 'timing', 'transfer', 'duplicate']
                            .contains(r['state']))
                    .toList();
                return RefreshIndicator(
                    onRefresh: _refresh,
                    child:
                        ListView(padding: const EdgeInsets.all(22), children: [
                      EmvilleHeading(DateFormat('MMMM yyyy').format(month),
                          eyebrow: 'Federal Bank / reconciliation',
                          subtitle:
                              'Review differences before approving ledger entries.'),
                      const SizedBox(height: 18),
                      EmvilleCallout(
                          leading: Text('$pending', style: Emville.heading(24)),
                          trailing: EmvilleTag(
                              completed ? 'Completed' : 'In review',
                              warning: !completed),
                          child:
                              const Text('Statement transactions need review')),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, children: [
                        TextButton.icon(
                            onPressed: () => _pdf(session['file_path']),
                            icon: const Icon(Icons.picture_as_pdf, size: 18),
                            label: const Text('Original PDF')),
                        TextButton.icon(
                            onPressed: _busy || completed
                                ? null
                                : () => _act(() => _repo.compare(widget.id)),
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text('Compare again'))
                      ]),
                      Text(
                          'Opening ${rupees(session['opening_balance'])} · Closing ${rupees(session['closing_balance'])}',
                          style: const TextStyle(
                              fontSize: 12, color: Emville.muted)),
                      const SizedBox(height: 8),
                      Text(
                          'Bank net movement ${rupees(bankNet)} · Approved ledger movement ${rupees(ledgerNet)}\nDifference ${rupees(bankNet - ledgerNet)} (including timing differences)',
                          style: const TextStyle(
                              fontSize: 12, color: Emville.muted)),
                      if (staleLinks > 0)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 10),
                            child: Text(
                                'A linked ledger entry changed after matching. Review its link before completing this month.',
                                style: TextStyle(
                                    color: Colors.red, fontSize: 12))),
                      if (_busy) const LinearProgressIndicator(),
                      const EmvilleSectionTitle('Statement transactions'),
                      EmvilleTabs(
                          labels: const ['Needs review', 'All'],
                          selected: _filter,
                          onSelected: (v) => setState(() => _filter = v)),
                      if (shown.isEmpty)
                        const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                                'No statement transactions awaiting review.')),
                      for (final r in shown)
                        Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(color: Emville.line))),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      '${r['date']} · ${r['transaction_type'] == 'income' ? '+' : '−'}${rupees(r['amount'])}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Text(r['description'],
                                      style: const TextStyle(fontSize: 12)),
                                  if ((r['reference'] ?? '').isNotEmpty)
                                    Text('Reference: ${r['reference']}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Emville.muted)),
                                  const SizedBox(height: 8),
                                  Align(
                                      alignment: Alignment.centerLeft,
                                      child: EmvilleTag(
                                          r['state']
                                              .toString()
                                              .replaceAll('_', ' '),
                                          warning: r['state'] != 'matched')),
                                  if (r['resolution_note'] != null)
                                    Text(r['resolution_note'],
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: Emville.muted)),
                                  for (final p in proposals.where((p) =>
                                      p['line_id'] == r['id'] &&
                                      p['status'] == 'pending')) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                        '${p['kind'] == 'adjustment' ? 'Proposed adjustment' : 'Proposed missing entry'}: ${p['transaction_type']} ${rupees(p['amount'])}',
                                        style: const TextStyle(fontSize: 12)),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                        onPressed: _busy || completed
                                            ? null
                                            : () => _approve(r, p),
                                        child: const Text(
                                            'Review proposal & approve')),
                                  ],
                                  if (!completed)
                                    TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () => _resolve(r, ledger),
                                        child: const Text(
                                            'Link existing entry / explain difference')),
                                  if (!completed &&
                                      ['unmatched', 'review']
                                          .contains(r['state']) &&
                                      !proposals.any((p) =>
                                          p['line_id'] == r['id'] &&
                                          p['status'] == 'pending'))
                                    TextButton(
                                        onPressed:
                                            _busy ? null : () => _distinct(r),
                                        child: const Text(
                                            'Propose separate bank entry')),
                                ])),
                      EmvilleSectionTitle('Ledger entries not on statement',
                          trailing: Text('${missingLedger.length}',
                              style: const TextStyle(fontSize: 12))),
                      const Text(
                          'All main-ledger entries are compared for this bank account. Document timing differences, non-bank items and possible duplicates below.',
                          style: TextStyle(fontSize: 12, color: Emville.muted)),
                      for (final l in missingLedger) ...[
                        EmvilleTile(
                            icon: Icons.receipt_long_outlined,
                            title:
                                '${l['transaction_type']} ${rupees(l['amount'])}',
                            subtitle:
                                '${l['date']} · ${l['payee_payer_name'] ?? l['remarks'] ?? ''}',
                            trailing: reviews.any((v) =>
                                    v['ledger_id'] == l['id'] &&
                                    mapEquals(
                                        Map<String, dynamic>.from(
                                            v['ledger_snapshot']),
                                        l))
                                ? const EmvilleTag('Noted')
                                : null,
                            onTap: () => _ledgerReview(l)),
                        for (final p in reversals.where((p) =>
                            p['base_ledger_id'] == l['id'] &&
                            p['status'] == 'pending'))
                          FilledButton(
                              onPressed: _busy || completed
                                  ? null
                                  : () => _reversal(p),
                              child: Text(
                                  'Approve reversal · ${rupees(p['amount'])}')),
                        for (final v
                            in reviews.where((v) => v['ledger_id'] == l['id']))
                          Text('${v['classification']}: ${v['note']}',
                              style: const TextStyle(
                                  fontSize: 11, color: Emville.muted)),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _act(
                                  () => _repo.complete(widget.id, !completed)),
                          child: Text(completed
                              ? 'Reopen for review'
                              : 'Complete monthly review')),
                      if (!completed)
                        TextButton(
                            onPressed: _busy ? null : _discard,
                            child: const Text('Discard draft & replace PDF')),
                      const EmvilleSectionTitle('Review history'),
                      for (final a
                          in List<Map<String, dynamic>>.from(data['notes']))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                                '${DateFormat('d MMM, h:mm a').format(DateTime.parse(a['created_at']).toLocal())} · ${actorName(a['actor'])} · ${a['action']}\n${a['note']}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: Emville.muted,
                                    height: 1.5))),
                    ]));
              })));
}

class _ApprovalDialog extends StatefulWidget {
  const _ApprovalDialog({required this.line, required this.proposal});
  final Map<String, dynamic> line, proposal;
  @override
  State<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends State<_ApprovalDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  late TextEditingController _payee;
  @override
  void initState() {
    super.initState();
    _payee = TextEditingController(text: widget.line['description']);
  }

  @override
  void dispose() {
    _note.dispose();
    _payee.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Approve & post entry?'),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            '${widget.proposal['transaction_type']} · ${rupees(widget.proposal['amount'])}'),
                        const SizedBox(height: 10),
                        const Text(
                            'Approve only genuine business income or expense. Transfers, cash deposits and timing differences may not need a new ledger entry.',
                            style: TextStyle(fontSize: 12)),
                        const SizedBox(height: 16),
                        TextFormField(
                            controller: _payee,
                            decoration: const InputDecoration(
                                labelText: 'Payee / payer'),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Enter the payee or payer'
                                : null),
                        const SizedBox(height: 12),
                        TextFormField(
                            controller: _note,
                            maxLines: 3,
                            decoration: const InputDecoration(
                                labelText: 'Approval note'),
                            validator: (v) => (v ?? '').trim().isEmpty
                                ? 'Explain this entry'
                                : null),
                      ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(
                        context, (_note.text.trim(), _payee.text.trim()));
                  }
                },
                child: const Text('Approve & post'))
          ]);
}

class _ResolutionDialog extends StatefulWidget {
  const _ResolutionDialog(
      {required this.line, required this.ledger, this.ledgerOnly = false});
  final Map<String, dynamic> line;
  final List<Map<String, dynamic>> ledger;
  final bool ledgerOnly;
  @override
  State<_ResolutionDialog> createState() => _ResolutionDialogState();
}

class _ResolutionDialogState extends State<_ResolutionDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  String _action = 'timing';
  String? _ledger;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidates = widget.ledger
        .where((l) =>
            l['transaction_status'] == 'approved' &&
            (_action == 'adjustment' ||
                (l['transaction_type'] == widget.line['transaction_type'] &&
                    l['amount'] == widget.line['amount'])))
        .toList();
    return AlertDialog(
        title: Text(widget.ledgerOnly
            ? 'Explain ledger difference'
            : 'Resolve bank transaction'),
        content: SingleChildScrollView(
            child: Form(
                key: _form,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: _action,
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                            value: 'timing',
                            child: Text('Timing difference / follow up')),
                        DropdownMenuItem(
                            value: widget.ledgerOnly ? 'non_bank' : 'transfer',
                            child: const Text('Transfer / not a bank expense')),
                        const DropdownMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicate — review separately')),
                        if (!widget.ledgerOnly) ...[
                          const DropdownMenuItem(
                              value: 'link',
                              child: Text('Link an existing ledger entry')),
                          const DropdownMenuItem(
                              value: 'adjustment',
                              child: Text('Propose an amount correction')),
                          const DropdownMenuItem(
                              value: 'unmatched',
                              child: Text('Needs further review'))
                        ],
                      ],
                      onChanged: (v) => setState(() => _action = v!)),
                  if (_action == 'link' || _action == 'adjustment')
                    DropdownButtonFormField<String>(
                        initialValue: _ledger,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Matching approved ledger entry'),
                        items: candidates
                            .map((l) => DropdownMenuItem(
                                value: l['id'].toString(),
                                child: Text(
                                    '${l['date']} · ${l['payee_payer_name'] ?? l['remarks'] ?? ''}',
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => _ledger = v,
                        validator: (v) =>
                            v == null ? 'Choose a matching entry' : null),
                  const SizedBox(height: 16),
                  TextFormField(
                      controller: _note,
                      maxLines: 3,
                      decoration: const InputDecoration(
                          labelText: 'Review note / follow-up'),
                      validator: (v) => (v ?? '').trim().isEmpty
                          ? 'Add your review note'
                          : null),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.pop(context, (_action, _note.text.trim(), _ledger));
                }
              },
              child: const Text('Save review'))
        ]);
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog(
      {required this.title, required this.description, this.minimum = 1});
  final String title, description;
  final int minimum;
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.title),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(widget.description,
                        style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 16),
                    TextFormField(
                        controller: _note,
                        maxLines: 3,
                        decoration:
                            const InputDecoration(labelText: 'Review note'),
                        validator: (v) =>
                            (v ?? '').trim().length < widget.minimum
                                ? 'Add a clear review note'
                                : null),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(context, _note.text.trim());
                  }
                },
                child: const Text('Confirm'))
          ]);
}
