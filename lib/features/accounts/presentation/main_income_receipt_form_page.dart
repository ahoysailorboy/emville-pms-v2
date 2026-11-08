// lib/features/accounts/presentation/main_income_receipt_form_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:emville_pms/supabase_call.dart';

// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class MainIncomeReceiptFormPage extends StatefulWidget {
  const MainIncomeReceiptFormPage({super.key});

  @override
  State<MainIncomeReceiptFormPage> createState() =>
      _MainIncomeReceiptFormPageState();
}

class _MainIncomeReceiptFormPageState extends State<MainIncomeReceiptFormPage> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  DateTime _date = DateTime.now();
  final _amountCtrl = TextEditingController();
  final _payeeCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  // store DB token, show human label
  static const Map<String, String> _paymentModes = {
    'cash': 'Cash',
    'card': 'Card',
    'upi': 'UPI',
    'bank_transfer': 'Bank Transfer',
  };
  String _paymentMode = 'cash';

  String _enteredBy = 'User';
  File? _photoFile;
  bool _busy = false;

  // Emville theme colors
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  @override
  void initState() {
    super.initState();
    _resolveEnteredBy();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _payeeCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  // --- UI helpers (style only) ---
  InputDecoration _decoration(String label, {String? hint}) {
    final rs = ResponsiveSize.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      labelStyle: TextStyle(
        color: _green,
        fontWeight: FontWeight.w600,
        fontSize: rs.font(13),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs.radius(12)),
        borderSide: BorderSide(color: _green.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs.radius(12)),
        borderSide: BorderSide(color: _green.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs.radius(12)),
        borderSide: BorderSide(color: _gold, width: rs.w(2)),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: rs.space(14),
        vertical: rs.space(12),
      ),
    );
  }

  BoxDecoration _sectionBox() {
    final rs = ResponsiveSize.of(context);
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(rs.radius(14)),
      border: Border.all(color: _green.withValues(alpha: 0.18)),
      boxShadow: [
        BoxShadow(
          color: _green.withValues(alpha: 0.06),
          blurRadius: rs.w(10),
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  TextStyle get _sectionTitle {
    final rs = ResponsiveSize.of(context);
    return TextStyle(
      fontSize: rs.font(16),
      fontWeight: FontWeight.w800,
      color: _green,
    );
  }

  // --- existing logic (unchanged) ---
  Future<void> _resolveEnteredBy() async {
    final user = _sb.auth.currentUser;
    String name = 'User';
    if (user != null) {
      try {
        // Prefer users.full_name where uid = auth.uid()
        final row = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('full_name')
              .eq('uid', user.id)
              .maybeSingle();
        });
        final dbName = row?['full_name'] as String?;
        if (dbName != null && dbName.trim().isNotEmpty) {
          name = dbName.trim();
        } else {
          // fallbacks
          final metaFull = user.userMetadata?['full_name'] as String?;
          final metaName = user.userMetadata?['name'] as String?;
          name =
              (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
                  .toString()
                  .trim();
        }
      } catch (_) {
        final metaFull = user.userMetadata?['full_name'] as String?;
        final metaName = user.userMetadata?['name'] as String?;
        name = (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
            .toString()
            .trim();
      }
    }
    if (mounted) setState(() => _enteredBy = name);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source, imageQuality: 85);
    if (x != null) setState(() => _photoFile = File(x.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final rs = ResponsiveSize.of(context);
    final df = DateFormat('yyyy-MM-dd');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Income Receipt'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Date: ${df.format(_date)}'),
              Text('Amount: ₹${_amountCtrl.text}'),
              Text('Payment Mode: ${_paymentModes[_paymentMode]}'),
              if (_payeeCtrl.text.trim().isNotEmpty)
                Text('Payee: ${_payeeCtrl.text.trim()}'),
              if (_remarksCtrl.text.trim().isNotEmpty)
                Text('Remarks: ${_remarksCtrl.text.trim()}'),
              Text('Entered by: $_enteredBy'),
              if (_photoFile != null) ...[
                SizedBox(height: rs.space(8)),
                const Text('Photo: will be uploaded to receipts bucket'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Edit'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _gold,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _save();
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        _snack('Not signed in');
        return;
      }

      final df = DateFormat('yyyy-MM-dd');
      final dateStr = df.format(_date);
      final amount = double.parse(_amountCtrl.text);

      // 1) Insert the row first (without attachment_path)
      final inserted = await supabaseCall(() async {
        return await _sb
            .from('main_ledger')
            .insert({
              'date': dateStr, // 1
              'amount': amount, // 2
              'transaction_type': 'income', // 3
              'payee_payer_name': _payeeCtrl.text.trim().isEmpty
                  ? null
                  : _payeeCtrl.text.trim(), // 4
              'remarks': _remarksCtrl.text.trim().isEmpty
                  ? null
                  : _remarksCtrl.text.trim(), // 5
              'transaction_status': 'pending', // 6
              'created_by': _enteredBy, // 7
              'approved_by': null, // 8
              'attachment_path': null, // 9 (patch later)
              'payment_mode': _paymentMode, // 10
              'account_balance': null, // 11
              'creator_uuid': user.id, // 12
              'created_time': DateTime.now().toIso8601String(), // 13
            })
            .select('id')
            .single();
      });

      final ledgerId = inserted['id'] as String;

      // 2) Upload photo (optional) and patch attachment_path
      if (_photoFile != null) {
        final objectPath =
            'main_ledger/${user.id}/$ledgerId-${const Uuid().v4()}.jpg';
        try {
          await supabaseCall(() async {
            return await _sb.storage
                .from('receipts')
                .upload(objectPath, _photoFile!);
          });
          await supabaseCall(() async {
            return await _sb
                .from('main_ledger')
                .update({'attachment_path': objectPath}).eq('id', ledgerId);
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved without photo (storage error): $e')),
          );
        }
      }

      if (!mounted) return;
      _snack('Income receipt saved');
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack('DB error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to save receipt');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: _gold),
        title: Text(
          'Income Receipts',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      backgroundColor: const Color(0xFFF6F7F7),
      body: SafeArea(
        minimum: EdgeInsets.all(rs.space(16)),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // SECTION: Basics
              Container(
                decoration: _sectionBox(),
                padding: EdgeInsets.fromLTRB(
                  rs.space(14),
                  rs.space(14),
                  rs.space(14),
                  rs.space(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Basic Details', style: _sectionTitle),
                    SizedBox(height: rs.space(12)),

                    // Date
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Date',
                        style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w600,
                          fontSize: rs.font(13),
                        ),
                      ),
                      subtitle: Text(
                        df.format(_date),
                        style: TextStyle(fontSize: rs.font(16)),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.date_range,
                            color: _green, size: rs.icon(22)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _date = picked);
                        },
                      ),
                    ),
                    SizedBox(height: rs.space(12)),

                    // Amount
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration('Amount (₹)'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Amount is required';
                        }
                        final parsed = double.tryParse(v);
                        if (parsed == null) return 'Enter a valid number';
                        if (parsed <= 0) {
                          return 'Amount must be greater than zero';
                        }
                        return null;
                      },
                    ),
                    SizedBox(height: rs.space(12)),

                    // Payment Mode
                    InputDecorator(
                      decoration: _decoration('Payment Mode'),
                      child: DropdownButtonHideUnderline(
                        child: IconTheme(
                          data: IconThemeData(color: _green, size: rs.icon(20)),
                          child: DropdownButton<String>(
                            value: _paymentMode,
                            isExpanded: true,
                            items: _paymentModes.entries
                                .map(
                                  (e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: Text(
                                      e.value,
                                      style: TextStyle(fontSize: rs.font(14)),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => _paymentMode = v!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.space(14)),

              // SECTION: Parties & Notes
              Container(
                decoration: _sectionBox(),
                padding: EdgeInsets.fromLTRB(
                  rs.space(14),
                  rs.space(14),
                  rs.space(14),
                  rs.space(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Parties & Notes', style: _sectionTitle),
                    SizedBox(height: rs.space(12)),

                    // Payee
                    TextFormField(
                      controller: _payeeCtrl,
                      decoration: _decoration(
                        'Payee Name',
                        hint: 'Guest / OTA / Direct booking name',
                      ),
                    ),
                    SizedBox(height: rs.space(12)),

                    // Remarks
                    TextFormField(
                      controller: _remarksCtrl,
                      decoration: _decoration(
                        'Remarks (Check-in / Check-out dates)',
                      ),
                      maxLines: 3,
                    ),
                    SizedBox(height: rs.space(12)),

                    // Entered By (read-only)
                    InputDecorator(
                      decoration: _decoration('Entered By'),
                      child: Text(
                        _enteredBy,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _green,
                          fontSize: rs.font(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: rs.space(14)),

              // SECTION: Attachment
              Container(
                decoration: _sectionBox(),
                padding: EdgeInsets.fromLTRB(
                  rs.space(14),
                  rs.space(14),
                  rs.space(14),
                  rs.space(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Attachment', style: _sectionTitle),
                    SizedBox(height: rs.space(12)),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickPhoto(ImageSource.camera),
                            icon: Icon(Icons.photo_camera_outlined,
                                size: rs.icon(18)),
                            label: Text('Take Photo',
                                style: TextStyle(fontSize: rs.font(14))),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: BorderSide(
                                  color: _green.withValues(alpha: 0.35)),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(rs.radius(12)),
                              ),
                              padding: EdgeInsets.symmetric(
                                vertical: rs.space(12),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: rs.space(8)),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickPhoto(ImageSource.gallery),
                            icon: Icon(Icons.photo_library_outlined,
                                size: rs.icon(18)),
                            label: Text('Pick from Gallery',
                                style: TextStyle(fontSize: rs.font(14))),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: BorderSide(
                                  color: _green.withValues(alpha: 0.35)),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(rs.radius(12)),
                              ),
                              padding: EdgeInsets.symmetric(
                                vertical: rs.space(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_photoFile != null) ...[
                      SizedBox(height: rs.space(12)),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(rs.radius(12)),
                        child: Image.file(_photoFile!, height: rs.h(160)),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(height: rs.space(18)),

              // Submit
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _gold,
                    padding: EdgeInsets.symmetric(
                      vertical: rs.space(14),
                      horizontal: rs.space(16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(rs.radius(12)),
                    ),
                    textStyle: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: rs.font(14),
                    ),
                  ),
                  child: _busy
                      ? SizedBox(
                          height: rs.icon(18),
                          width: rs.icon(18),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2.6,
                            valueColor: AlwaysStoppedAnimation<Color>(_gold),
                          ),
                        )
                      : const Text('Review & Confirm'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
