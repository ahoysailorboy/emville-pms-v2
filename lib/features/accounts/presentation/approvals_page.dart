import '../data/finance_access.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';

class ApprovalsPage extends StatefulWidget {
  const ApprovalsPage({super.key, this.initialFilter = 'All'});
  final String initialFilter;
  @override
  State<ApprovalsPage> createState() => _ApprovalsPageState();
}

class _ApprovalsPageState extends State<ApprovalsPage> {
  final _sb = Supabase.instance.client;
  late String _filter;
  String? _role, _busy;
  late Future<List<Map<String, dynamic>>> _entries;
  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _entries = _load();
    _resolveRole();
  }

  Future<void> _resolveRole() async {
    final allowed = await FinanceAccess.isOwnerOrAdmin(_sb);
    if (mounted) setState(() => _role = allowed ? 'admin' : null);
  }

  bool _allowed(Map<String, dynamic> row) =>
      _role == 'owner' || _role == 'admin';
  Future<List<Map<String, dynamic>>> _load() async {
    final privileged = await FinanceAccess.isOwnerOrAdmin(_sb);
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return [];
    Future<List<Map<String, dynamic>>> pending(
        String table, String fields) async {
      var query =
          _sb.from(table).select(fields).eq('transaction_status', 'pending');
      if (!privileged) query = query.eq('creator_uuid', uid);
      return await query.order('date').order('created_time');
    }

    final results = await Future.wait([
      pending('main_ledger',
          'id,date,amount,transaction_type,payee_payer_name,remarks,transaction_status,created_by,approved_by,attachment_path,payment_mode,created_time'),
      pending('petty_cash_ledger',
          'id,date,amount,transaction_type,remarks,attachment_path,transaction_status,entered_by,approved_by,created_time'),
    ]);
    final entries = <Map<String, dynamic>>[
      for (final r in results[0])
        {
          ...r,
          '_kind': 'Main',
          '_table': 'main_ledger',
          '_by': r['created_by']
        },
      for (final r in results[1])
        {
          ...r,
          '_kind': 'Petty cash',
          '_table': 'petty_cash_ledger',
          '_by': r['entered_by']
        }
    ];
    entries.sort((a, b) =>
        (b['date']?.toString() ?? '').compareTo(a['date']?.toString() ?? ''));
    return entries;
  }

  Future<void> _refresh() async {
    setState(() {
      _entries = _load();
    });
    try {
      await _entries;
    } catch (_) {}
  }

  String _title(Map<String, dynamic> row) {
    for (final key in ['remarks', 'payee_payer_name']) {
      final text = row[key]?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return row['transaction_type'] == 'income' ? 'Income receipt' : 'Expense';
  }

  Future<String> _myName() async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'User';
    try {
      final row = await supabaseCall(() => _sb
          .from('users')
          .select('full_name')
          .eq('uid', user.id)
          .maybeSingle());
      final name = row?['full_name']?.toString().trim() ?? '';
      if (name.isNotEmpty) return name;
    } catch (_) {}
    return (user.userMetadata?['full_name'] ??
            user.userMetadata?['name'] ??
            user.email?.split('@').first ??
            'User')
        .toString();
  }

  Future<void> _act(Map<String, dynamic> row, {bool delete = false}) async {
    if (!_allowed(row) || _busy != null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(delete ? 'Delete entry?' : 'Approve entry?'),
                content: Text(delete
                    ? 'Do you really want to delete this entry? This cannot be undone.'
                    : 'Approve ${_title(row)} for ${rupees((row['amount'] as num?) ?? 0)}?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: Text(delete ? 'Delete' : 'Approve'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = '${row['_table']}/${row['id']}');
    try {
      if (delete) {
        await supabaseCall(() =>
            _sb.from(row['_table'] as String).delete().eq('id', row['id']));
      } else {
        final name = await _myName();
        await supabaseCall(() => _sb
            .from(row['_table'] as String)
            .update({'transaction_status': 'approved', 'approved_by': name}).eq(
                'id', row['id']));
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(delete ? 'Entry deleted' : 'Entry approved')));
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(delete
                ? 'Could not delete this entry. Please try again.'
                : 'Could not approve this entry. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<String?> _receipt(Map<String, dynamic> row) async {
    final path = row['attachment_path']?.toString();
    if (path == null || path.isEmpty) return null;
    return supabaseCall(
        () => _sb.storage.from('receipts').createSignedUrl(path, 600));
  }

  void _details(Map<String, dynamic> row) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text(_title(row), style: Emville.heading(24)),
              content: SizedBox(
                  width: 350,
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(rupees((row['amount'] as num?) ?? 0),
                            style: Emville.heading(26)),
                        const SizedBox(height: 14),
                        for (final detail in <String, dynamic>{
                          'Account': row['_kind'],
                          'Date': row['date'],
                          'Type': row['transaction_type'],
                          'Payee / payer': row['payee_payer_name'],
                          'Payment mode': row['payment_mode'],
                          'Entered by': row['_by'],
                          'Notes': row['remarks'],
                          'Status': row['transaction_status']
                        }.entries)
                          if (detail.value != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('${detail.key}: ${detail.value}',
                                    style: const TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 12,
                                        height: 1.5))),
                        FutureBuilder<String?>(
                            future: _receipt(row),
                            builder: (context, snapshot) {
                              if (snapshot.hasError) {
                                return const Text(
                                    'Receipt could not be loaded.',
                                    style: TextStyle(
                                        fontFamily: 'Roboto', fontSize: 12));
                              }
                              if (snapshot.connectionState !=
                                  ConnectionState.done) {
                                return const LinearProgressIndicator();
                              }
                              if (snapshot.data == null) {
                                return const Text('No receipt attached.',
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 12,
                                        color: Emville.muted));
                              }
                              return GestureDetector(
                                  onTap: () => showDialog<void>(
                                      context: context,
                                      builder: (_) => Dialog(
                                          child: InteractiveViewer(
                                              child: Image.network(
                                                  snapshot.data!)))),
                                  child: Image.network(snapshot.data!,
                                      height: 160,
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stack) =>
                                          const Text(
                                              'Receipt preview unavailable.')));
                            })
                      ]))),
              actions: [
                if (_allowed(row))
                  TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _act(row, delete: true);
                      },
                      child: const Text('Delete')),
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'))
              ]));
  @override
  Widget build(BuildContext context) => EmvillePage(
      child: EmvilleBody(
          child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
                  children: [
                    const EmvilleHeading('Pending approvals',
                        eyebrow: 'Owner / Admin workspace',
                        subtitle: 'Review the details. Keep records in order.'),
                    const SizedBox(height: 20),
                    EmvilleTabs(
                        labels: const ['All', 'Main', 'Petty cash'],
                        selected: _filter,
                        onSelected: (value) => setState(() => _filter = value)),
                    FutureBuilder<List<Map<String, dynamic>>>(
                        future: _entries,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return EmvilleError(onRetry: _refresh);
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                                padding: EdgeInsets.all(30),
                                child:
                                    Center(child: CircularProgressIndicator()));
                          }
                          final rows = snapshot.data!
                              .where((r) =>
                                  _filter == 'All' || r['_kind'] == _filter)
                              .toList();
                          if (rows.isEmpty) {
                            return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 30),
                                child: Text('No pending approvals.',
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 12,
                                        color: Emville.muted)));
                          }
                          return Column(children: [
                            for (final row in rows)
                              Container(
                                  margin: const EdgeInsets.only(top: 14),
                                  padding: const EdgeInsets.all(17),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFFFFDF7),
                                      border: Border.all(color: Emville.line),
                                      borderRadius: BorderRadius.circular(13)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              const EmvilleTag('Pending review',
                                                  warning: true),
                                              Text(
                                                  shortDate(
                                                      row['date']?.toString() ??
                                                          ''),
                                                  style: const TextStyle(
                                                      fontFamily: 'Roboto',
                                                      fontSize: 10,
                                                      color: Emville.muted))
                                            ]),
                                        const SizedBox(height: 10),
                                        Text(_title(row),
                                            style: Emville.heading(19)),
                                        const SizedBox(height: 7),
                                        Row(children: [
                                          Expanded(
                                              child: Text(
                                                  '${row['_kind']} account · ${row['transaction_type'] ?? 'Entry'}\nEntered by ${row['_by'] ?? '—'} · ${shortDate(row['date']?.toString() ?? '')}',
                                                  style: const TextStyle(
                                                      fontFamily: 'Roboto',
                                                      fontSize: 11,
                                                      color: Emville.muted,
                                                      height: 1.6))),
                                          const SizedBox(width: 12),
                                          Text(
                                              rupees(
                                                  (row['amount'] as num?) ?? 0),
                                              style: Emville.heading(24))
                                        ]),
                                        const SizedBox(height: 14),
                                        Row(children: [
                                          Expanded(
                                              child: OutlinedButton(
                                                  onPressed: () =>
                                                      _details(row),
                                                  child: const Text(
                                                      'View details'))),
                                          if (_allowed(row)) ...[
                                            const SizedBox(width: 8),
                                            Expanded(
                                                child: FilledButton(
                                                    style:
                                                        FilledButton.styleFrom(
                                                            minimumSize:
                                                                const Size(
                                                                    44, 38)),
                                                    onPressed: _busy == null
                                                        ? () => _act(row)
                                                        : null,
                                                    child: Text(_busy ==
                                                            '${row['_table']}/${row['id']}'
                                                        ? 'Approving…'
                                                        : 'Approve')))
                                          ]
                                        ]),
                                      ]))
                          ]);
                        }),
                    const SizedBox(height: 18),
                    const Text(
                        'Approval controls are available for owner/admin roles.',
                        style: TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 10,
                            color: Emville.muted,
                            height: 1.5)),
                  ]))));
}
