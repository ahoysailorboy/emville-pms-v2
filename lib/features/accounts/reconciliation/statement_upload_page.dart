import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import '../data/finance_access.dart';
import 'reconciliation_repository.dart';
import 'statement_review_page.dart';

int? bankMoneyCents(String text, {bool signed = false}) {
  final s = text.replaceAll(RegExp(r'[,₹\s]'), '');
  if (!(signed ? RegExp(r'^-?\d+(\.\d{1,2})?$') : RegExp(r'^\d+(\.\d{1,2})?$'))
      .hasMatch(s)) {
    return null;
  }
  final parts = s.replaceFirst('-', '').split('.');
  final value = int.parse(parts[0]) * 100 +
      int.parse(parts.length == 1 ? '0' : parts[1].padRight(2, '0'));
  return s.startsWith('-') ? -value : value;
}

class StatementUploadPage extends StatefulWidget {
  const StatementUploadPage({super.key});
  @override
  State<StatementUploadPage> createState() => _StatementUploadPageState();
}

class _StatementUploadPageState extends State<StatementUploadPage> {
  final _repo = BankReconciliationRepository(Supabase.instance.client);
  final _opening = TextEditingController(), _closing = TextEditingController();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month - 1);
  List<Map<String, dynamic>> _lines = [];
  List<String> _warnings = [];
  String? _path, _sha, _id, _filename;
  String _pdfText = '';
  bool _busy = false, _confirmed = false;
  @override
  void dispose() {
    _opening.dispose();
    _closing.dispose();
    super.dispose();
  }

  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await FinanceAccess.isOwnerOrAdmin(_repo.client)) {
        _message('Only admins and owners can upload bank statements.');
        return;
      }
      final files = await FilePicker.pickFiles(
          type: FileType.custom, allowedExtensions: ['pdf']);
      if (files.isEmpty) return;
      final bytes = await files.single.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024 ||
          bytes.length < 5 ||
          String.fromCharCodes(bytes.take(5)) != '%PDF-') {
        _message('Choose a bank statement PDF under 10 MB.');
        return;
      }
      if (!mounted) return;
      final id = const Uuid().v4();
      final path = '${_repo.client.auth.currentUser!.id}/$id.pdf';
      await _repo.client.storage.from('bank-statements').uploadBinary(
          path, bytes,
          fileOptions: const FileOptions(contentType: 'application/pdf'));
      if (mounted) {
        setState(() {
          _id = id;
          _path = path;
          _sha = sha256.convert(bytes).toString();
          _filename = files.single.name;
          _confirmed = false;
          _lines = [];
          _warnings = [];
        });
      }
      try {
        final response = await _repo.client.functions
            .invoke('bank_statement_extract', body: {'path': path});
        if (response.status != 200 || response.data['error'] != null) {
          throw StateError('PDF reading failed');
        }
        if (mounted) {
          setState(() {
            _lines = List<Map<String, dynamic>>.from(response.data['lines']);
            _warnings = List<String>.from(response.data['warnings']);
            _pdfText = response.data['text'] ?? '';
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() => _warnings = [
                'The PDF is saved, but its transactions could not be read. You can enter them manually from the original statement.'
              ]);
        }
      }
    } catch (_) {
      _message(
          'Could not upload the statement. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _monthPick() async {
    final now = DateTime.now();
    final last = DateTime(now.year, now.month, 0);
    final d = await showDatePicker(
        context: context,
        initialDate: _month,
        firstDate: DateTime(2020),
        lastDate: last);
    if (d != null && mounted) {
      setState(() {
        _month = DateTime(d.year, d.month);
        _confirmed = false;
      });
    }
  }

  Future<void> _edit([int? index]) async {
    final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => BankLineDialog(
            line: index == null ? null : _lines[index], month: _month));
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          _lines.add(result);
        } else {
          _lines[index] = result;
        }
        _confirmed = false;
      });
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    final opening = bankMoneyCents(_opening.text, signed: true),
        closing = bankMoneyCents(_closing.text, signed: true);
    if (_id == null ||
        _path == null ||
        opening == null ||
        closing == null ||
        !_confirmed) {
      _message(
          'Upload the PDF, review transactions and confirm both statement balances.');
      return;
    }
    if (_lines.any((r) {
      final d = DateTime.tryParse(r['date'].toString());
      return d == null || d.year != _month.year || d.month != _month.month;
    })) {
      _message(
          'All statement transactions must belong to the selected month. Review their dates.');
      return;
    }
    final net = _lines.fold<int>(
        0,
        (sum, r) =>
            sum +
            (r['transaction_type'] == 'income' ? 1 : -1) *
                (bankMoneyCents(r['amount'].toString()) ?? 0));
    if (opening + net != closing) {
      _message(
          'Opening balance plus transactions does not equal closing balance. Review missing or misread transactions.');
      return;
    }
    setState(() => _busy = true);
    var saved = false;
    try {
      await _repo.client.rpc('create_bank_reconciliation', params: {
        'p_id': _id,
        'p_month': DateFormat('yyyy-MM-dd').format(_month),
        'p_file_path': _path,
        'p_file_sha256': _sha,
        'p_opening': (opening / 100).toStringAsFixed(2),
        'p_closing': (closing / 100).toStringAsFixed(2),
        'p_lines': _lines
      });
      saved = true;
      await _repo.compare(_id!);
    } on PostgrestException catch (e) {
      _message(e.code == '23505'
          ? 'A statement for this month or the same PDF is already uploaded. Open the existing monthly review.'
          : e.message);
    } catch (_) {
      _message(saved
          ? 'Statement saved. Open its monthly review and tap Compare again.'
          : 'Could not save the statement. Please retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (saved && mounted) {
      await Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => StatementReviewPage(id: _id!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final net = _lines.fold<int>(
        0,
        (sum, r) =>
            sum +
            (r['transaction_type'] == 'income' ? 1 : -1) *
                (bankMoneyCents(r['amount'].toString()) ?? 0));
    final opening = bankMoneyCents(_opening.text, signed: true),
        closing = bankMoneyCents(_closing.text, signed: true);
    final difference =
        opening == null || closing == null ? null : opening + net - closing;
    return EmvillePage(
        section: 2,
        child: EmvilleBody(
            child: ListView.builder(
                padding: const EdgeInsets.all(22),
                itemCount: _lines.length + 2,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const EmvilleHeading('Upload bank statement',
                              eyebrow: 'Accounts / reconciliation',
                              subtitle:
                                  'Federal Bank · Review the PDF before comparing with the ledger.'),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                              onPressed: _busy ? null : _monthPick,
                              icon: const Icon(Icons.calendar_month),
                              label:
                                  Text(DateFormat('MMMM yyyy').format(_month))),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: _busy ? null : _pick,
                              icon: const Icon(Icons.picture_as_pdf),
                              label: Text(_busy
                                  ? 'Reading statement…'
                                  : _filename ?? 'Choose PDF statement')),
                          if (_busy) const LinearProgressIndicator(),
                          for (final w in _warnings)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Text(w,
                                    style: const TextStyle(
                                        color: Emville.muted, fontSize: 12))),
                          if (_pdfText.isNotEmpty)
                            ExpansionTile(
                                title:
                                    const Text('Read extracted statement text'),
                                children: [
                                  SelectableText(_pdfText,
                                      style: const TextStyle(fontSize: 11))
                                ]),
                          const EmvilleSectionTitle('Review transactions'),
                          const Text(
                              'Check every date, debit and credit against the PDF. Correct or add rows before continuing.',
                              style: TextStyle(
                                  fontSize: 12, color: Emville.muted)),
                        ]);
                  }
                  if (i <= _lines.length) {
                    final r = _lines[i - 1];
                    return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${r['date']} · ${r['transaction_type'] == 'income' ? '+' : '−'}${rupees(num.parse(r['amount'].toString()))}'),
                        subtitle: Text(r['description'],
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        onTap: _busy ? null : () => _edit(i - 1),
                        trailing: IconButton(
                            tooltip: 'Remove transaction',
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _lines.removeAt(i - 1);
                                      _confirmed = false;
                                    }),
                            icon: const Icon(Icons.close, size: 18)));
                  }
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                            onPressed: _busy ? null : () => _edit(),
                            icon: const Icon(Icons.add),
                            label: const Text('Add statement transaction')),
                        const SizedBox(height: 20),
                        Text(
                            '${_lines.length} transactions · Net ${rupees(net / 100)}'),
                        const SizedBox(height: 14),
                        TextField(
                            controller: _opening,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Statement opening balance'),
                            onChanged: (_) =>
                                setState(() => _confirmed = false)),
                        const SizedBox(height: 14),
                        TextField(
                            controller: _closing,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true, signed: true),
                            decoration: const InputDecoration(
                                labelText: 'Statement closing balance'),
                            onChanged: (_) =>
                                setState(() => _confirmed = false)),
                        const SizedBox(height: 12),
                        if (difference != null)
                          Text(
                              difference == 0
                                  ? 'Statement totals agree.'
                                  : 'Statement difference: ${rupees(difference / 100)}',
                              style: TextStyle(
                                  color: difference == 0
                                      ? Emville.forest
                                      : Colors.red.shade700)),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _confirmed,
                            onChanged: _busy
                                ? null
                                : (v) =>
                                    setState(() => _confirmed = v ?? false),
                            title: Text(
                                _lines.isEmpty
                                    ? 'I checked the original PDF and confirm there were no transactions this month.'
                                    : 'I checked the transactions and balances against the original PDF.',
                                style: TextStyle(fontSize: 12))),
                        FilledButton(
                            onPressed: _busy ? null : _save,
                            child: const Text('Save & compare with ledger')),
                      ]);
                })));
  }
}

class BankLineDialog extends StatefulWidget {
  const BankLineDialog({super.key, this.line, required this.month});
  final Map<String, dynamic>? line;
  final DateTime month;
  @override
  State<BankLineDialog> createState() => _BankLineDialogState();
}

class _BankLineDialogState extends State<BankLineDialog> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _date, _amount, _description, _reference;
  late String _type;
  @override
  void initState() {
    super.initState();
    _date = TextEditingController(
        text: widget.line?['date'] ??
            DateFormat('yyyy-MM-dd').format(widget.month));
    _amount =
        TextEditingController(text: widget.line?['amount']?.toString() ?? '');
    _description =
        TextEditingController(text: widget.line?['description'] ?? '');
    _reference = TextEditingController(text: widget.line?['reference'] ?? '');
    _type = widget.line?['transaction_type'] ?? 'expense';
  }

  @override
  void dispose() {
    for (final c in [_date, _amount, _description, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Statement transaction'),
          content: SingleChildScrollView(
              child: Form(
                  key: _form,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: _date,
                        decoration: const InputDecoration(
                            labelText: 'Date · YYYY-MM-DD'),
                        validator: (v) {
                          final d = DateTime.tryParse(v ?? '');
                          return d == null ||
                                  DateFormat('yyyy-MM-dd').format(d) != v ||
                                  d.year != widget.month.year ||
                                  d.month != widget.month.month
                              ? 'Enter a valid date in the selected month'
                              : null;
                        }),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        initialValue: _type,
                        decoration:
                            const InputDecoration(labelText: 'Bank entry'),
                        items: const [
                          DropdownMenuItem(
                              value: 'expense',
                              child: Text('Debit / money out')),
                          DropdownMenuItem(
                              value: 'income', child: Text('Credit / money in'))
                        ],
                        onChanged: (v) => _type = v!),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _amount,
                        decoration: const InputDecoration(labelText: 'Amount'),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        validator: (v) => (bankMoneyCents(v ?? '') ?? 0) <= 0
                            ? 'Enter a positive amount'
                            : null),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _description,
                        decoration:
                            const InputDecoration(labelText: 'Description'),
                        maxLines: 2,
                        validator: (v) => (v ?? '').trim().isEmpty
                            ? 'Enter a description'
                            : null),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: _reference,
                        decoration: const InputDecoration(
                            labelText: 'UTR / reference (optional)')),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () {
                  if (_form.currentState!.validate()) {
                    Navigator.pop(context, {
                      'date': _date.text.trim(),
                      'amount': (bankMoneyCents(_amount.text)! / 100)
                          .toStringAsFixed(2),
                      'transaction_type': _type,
                      'description': _description.text.trim(),
                      'reference': _reference.text.trim()
                    });
                  }
                },
                child: const Text('Save row'))
          ]);
}
