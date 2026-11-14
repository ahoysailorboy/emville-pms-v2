import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';

enum AccountEntryKind { income, expense, pettyReceipt }

class AccountEntryPage extends StatefulWidget {
  const AccountEntryPage({super.key, required this.kind, this.receiver = ''});
  final AccountEntryKind kind;
  final String receiver;
  @override
  State<AccountEntryPage> createState() => _AccountEntryPageState();
}

class _AccountEntryPageState extends State<AccountEntryPage> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController(),
      _receiver = TextEditingController(),
      _description = TextEditingController(),
      _reference = TextEditingController();
  final _client = Supabase.instance.client;
  DateTime _date = DateTime.now();
  String _mode = 'cash', _name = 'User';
  Uint8List? _attachment;
  String? _filename;
  bool _busy = false;
  bool get _petty => widget.kind == AccountEntryKind.pettyReceipt;
  bool get _income => widget.kind == AccountEntryKind.income;
  bool get _funding =>
      widget.kind == AccountEntryKind.expense &&
      _receiver.text.trim().toLowerCase() == 'petty cash';
  String get _title => _petty
      ? 'Petty cash receipt'
      : _income
          ? 'Add income'
          : 'Add expense';
  static const _modes = {
    'cash': 'Cash',
    'upi': 'UPI',
    'bank_transfer': 'Bank transfer',
  };
  @override
  void initState() {
    super.initState();
    _receiver.text = widget.receiver;
    if (widget.receiver == 'Petty cash') {
      _description.text = 'Petty cash funding';
    }
    _resolveName();
  }

  Future<void> _resolveName() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    var name = (user.userMetadata?['full_name'] ??
            user.userMetadata?['name'] ??
            user.email?.split('@').first ??
            'User')
        .toString();
    try {
      final row = await _client
          .from('users')
          .select('full_name')
          .eq('uid', user.id)
          .maybeSingle();
      final full = row?['full_name']?.toString().trim();
      if (full != null && full.isNotEmpty) name = full;
    } catch (_) {}
    if (mounted) setState(() => _name = name);
  }

  @override
  void dispose() {
    for (final c in [_amount, _receiver, _description, _reference]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (d != null && mounted) setState(() => _date = d);
  }

  Future<void> _attach() async {
    final option = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final item in <(String, IconData, String)>[
                ('camera', Icons.camera_alt_outlined, 'Take photo'),
                ('gallery', Icons.photo_library_outlined, 'Photo library'),
                ('file', Icons.attach_file, 'Choose file or PDF')
              ])
                ListTile(
                    leading: Icon(item.$2),
                    title: Text(item.$3),
                    onTap: () => Navigator.of(context).pop(item.$1))
            ])));
    if (option == null) return;
    try {
      Uint8List? bytes;
      String? name;
      if (option == 'file') {
        final result = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf']);
        if (result.isNotEmpty) {
          bytes = await result.single.readAsBytes();
          name = result.single.name;
        }
      } else {
        final photo = await ImagePicker().pickImage(
            source:
                option == 'camera' ? ImageSource.camera : ImageSource.gallery,
            imageQuality: 85);
        if (photo != null) {
          bytes = await photo.readAsBytes();
          name = photo.name;
        }
      }
      if (bytes != null && name != null && mounted) {
        setState(() {
          _attachment = bytes;
          _filename = name;
        });
      }
    } catch (_) {
      if (mounted) _snack('Could not attach the file. Please try again.');
    }
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Submit for approval?', style: Emville.heading(24)),
                content: Text(
                    '${_description.text.trim()}\n${rupees(double.parse(_amount.text.replaceAll(',', '')))}\n\nThis entry will be pending approval.${_funding ? ' A linked petty cash income is created automatically.' : ''}',
                    style: const TextStyle(fontSize: 12, height: 1.6)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Edit')),
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Confirm submission'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw const AuthException('Please sign in again.');
      final notes = [
        _description.text.trim(),
        if (_petty && _receiver.text.trim().isNotEmpty)
          'Paid to: ${_receiver.text.trim()}',
        if (_petty) 'Payment mode: ${_modes[_mode]}',
        if (_reference.text.trim().isNotEmpty)
          'Reference: ${_reference.text.trim()}'
      ].join('\n');
      final table = _petty ? 'petty_cash_ledger' : 'main_ledger';
      final row = <String, dynamic>{
        'date': DateFormat('yyyy-MM-dd').format(_date),
        'amount': double.parse(_amount.text.replaceAll(',', '')),
        'transaction_type': _income ? 'income' : 'expense',
        'remarks': notes,
        'transaction_status': 'pending',
        'approved_by': null,
        'attachment_path': null,
        'creator_uuid': user.id,
        'created_time': DateTime.now().toIso8601String(),
        if (_petty) 'entered_by': _name,
        if (!_petty) ...{
          'created_by': _name,
          'payee_payer_name': _funding ? 'Petty cash' : _receiver.text.trim(),
          'payment_mode': _mode,
          'account_balance': null
        }
      };
      // Funding is recorded exactly once. The database's existing link creates
      // the petty cash income; never insert a second top-up from the client.
      final inserted =
          await _client.from(table).insert(row).select('id').single();
      var attached = true;
      if (_attachment != null) {
        try {
          final ext =
              (_filename ?? 'receipt.jpg').split('.').last.toLowerCase();
          final path =
              '${_petty ? 'petty' : 'main_ledger'}/${user.id}/${inserted['id']}-${const Uuid().v4()}.$ext';
          await _client.storage
              .from('receipts')
              .uploadBinary(path, _attachment!,
                  fileOptions: FileOptions(
                      contentType: ext == 'pdf'
                          ? 'application/pdf'
                          : ext == 'png'
                              ? 'image/png'
                              : 'image/jpeg'));
          await _client
              .from(table)
              .update({'attachment_path': path}).eq('id', inserted['id']);
        } catch (_) {
          attached = false;
        }
      }
      if (!mounted) return;
      _snack(attached
          ? 'Entry submitted for approval.'
          : 'Entry submitted for approval, but its attachment could not be saved.');
      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (mounted) _snack(e.message);
    } on PostgrestException catch (e) {
      if (mounted) _snack('Could not save entry: ${e.message}');
    } catch (_) {
      if (mounted) _snack('Could not save entry. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
  Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 7),
      child: Text(text,
          style: const TextStyle(fontFamily: 'Roboto', fontSize: 11)));
  @override
  Widget build(BuildContext context) => EmvillePage(
      child: EmvilleBody(
          child: Form(
              key: _form,
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                  children: [
                    EmvilleHeading(_title,
                        eyebrow: _petty
                            ? 'Accounts / Daily spending'
                            : 'Accounts / Main ledger',
                        subtitle: _petty
                            ? 'Attach a receipt. Keep daily spending in order.'
                            : _income
                                ? 'Record money received. Attach its receipt.'
                                : 'Record a payment. Attach its receipt.'),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                _label('Amount (₹)'),
                                TextFormField(
                                    key: const ValueKey('account-entry-amount'),
                                    controller: _amount,
                                    enabled: !_busy,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    style: const TextStyle(fontSize: 12),
                                    decoration:
                                        const InputDecoration(hintText: '0.00'),
                                    validator: (value) {
                                      final n = double.tryParse(
                                          (value ?? '').replaceAll(',', ''));
                                      return n == null || !n.isFinite || n <= 0
                                          ? 'Enter a positive amount'
                                          : null;
                                    })
                              ])),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                _label('Date'),
                                OutlinedButton(
                                    onPressed: _busy ? null : _pickDate,
                                    style: OutlinedButton.styleFrom(
                                        minimumSize:
                                            const Size(double.infinity, 48)),
                                    child: Text(
                                        DateFormat('d MMM yyyy').format(_date),
                                        style: const TextStyle(fontSize: 11)))
                              ]))
                        ]),
                    _label(_income
                        ? 'Received from'
                        : _petty
                            ? 'Paid to'
                            : 'Receiver'),
                    TextFormField(
                        key: const ValueKey('account-entry-receiver'),
                        controller: _receiver,
                        enabled: !_busy,
                        onChanged: (_) => setState(() {}),
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                            hintText: _income
                                ? 'Guest or payer'
                                : _petty
                                    ? 'Store or supplier'
                                    : 'Supplier or Petty cash'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a ${_income ? 'payer' : 'receiver'}'
                            : null),
                    if (_funding)
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: EmvilleCallout(
                              child: Text(
                                  'Main ledger → Petty cash\nCreates a linked petty cash income automatically. Enter the funding amount once.'))),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                _label('Payment mode'),
                                DropdownButtonFormField<String>(
                                    initialValue: _mode,
                                    isExpanded: true,
                                    style: const TextStyle(
                                        fontSize: 12, color: Emville.ink),
                                    items: _modes.entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.key, child: Text(e.value)))
                                        .toList(),
                                    onChanged: _busy
                                        ? null
                                        : (v) => setState(() => _mode = v!))
                              ])),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                _label('Reference'),
                                TextFormField(
                                    controller: _reference,
                                    enabled: !_busy,
                                    style: const TextStyle(fontSize: 12),
                                    decoration: const InputDecoration(
                                        hintText: 'Optional'))
                              ]))
                        ]),
                    _label('Description'),
                    TextFormField(
                        key: const ValueKey('account-entry-description'),
                        controller: _description,
                        enabled: !_busy,
                        style: const TextStyle(fontSize: 12),
                        decoration: const InputDecoration(
                            hintText: 'What is this entry for?'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter a description'
                            : null),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                        onPressed: _busy ? null : _attach,
                        icon: const Icon(Icons.attach_file, size: 17),
                        label: Text(
                            _filename ?? 'Attach receipt or payment proof',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis)),
                    if (_filename != null)
                      Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                        _filename = null;
                                        _attachment = null;
                                      }),
                              child: const Text('Remove attachment',
                                  style: TextStyle(fontSize: 10)))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                          child: Text('Submitted by $_name',
                              style: const TextStyle(
                                  fontSize: 10, color: Emville.muted))),
                      const EmvilleTag('Pending approval', warning: true)
                    ]),
                    const SizedBox(height: 18),
                    FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Emville.paper))
                            : const Text('Submit for approval')),
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                            _funding
                                ? 'Both linked entries need review. No second top-up entry is needed.'
                                : 'Every entry, including owner/admin submissions, needs approval.',
                            style: const TextStyle(
                                fontSize: 10,
                                color: Emville.muted,
                                height: 1.6))),
                  ]))));
}
