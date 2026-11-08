// lib/features/accounts/presentation/petty_cash_bill_form_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class PettyCashBillFormPage extends StatefulWidget {
  const PettyCashBillFormPage({super.key});

  @override
  State<PettyCashBillFormPage> createState() => _PettyCashBillFormPageState();
}

// Emville theme colors
const Color _green = Color(0xFF103329);
const Color _gold = Color(0xFFD9A633);

class _PettyCashBillFormPageState extends State<PettyCashBillFormPage> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  DateTime _date = DateTime.now();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _enteredBy = 'User'; // resolved in initState

  File? _photoFile;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolveEnteredBy();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveEnteredBy() async {
    // Resolve from public.users.full_name where uid = auth.uid(),
    // then fall back to user metadata or email prefix.
    final user = _sb.auth.currentUser;
    final uid = user?.id;
    String name = 'User';

    if (uid != null) {
      try {
        final row = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('full_name')
              .eq('uid', uid) // <-- correct PK column
              .maybeSingle();
        });

        final fromUsers = row?['full_name'] as String?;
        if (fromUsers != null && fromUsers.trim().isNotEmpty) {
          name = fromUsers.trim();
        } else {
          final metaFull = user?.userMetadata?['full_name'] as String?;
          final metaName = user?.userMetadata?['name'] as String?;
          final fallback =
              metaFull ?? metaName ?? user?.email?.split('@').first;
          if (fallback != null && fallback.trim().isNotEmpty) {
            name = fallback.trim();
          }
        }
      } catch (_) {
        final metaFull = user?.userMetadata?['full_name'] as String?;
        final metaName = user?.userMetadata?['name'] as String?;
        final fallback = metaFull ?? metaName ?? user?.email?.split('@').first;
        if (fallback != null && fallback.trim().isNotEmpty) {
          name = fallback.trim();
        }
      }
    }

    if (mounted) setState(() => _enteredBy = name);
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final x = await picker.pickImage(source: source, imageQuality: 80);
    if (x != null) setState(() => _photoFile = File(x.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final df = DateFormat('yyyy-MM-dd');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Bill'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${df.format(_date)}'),
            Text('Amount: ₹${_amountCtrl.text}'),
            Text('Entered by: $_enteredBy'),
            const Text('Status: pending'),
            if (_notesCtrl.text.trim().isNotEmpty)
              Text('Notes: ${_notesCtrl.text.trim()}'),
            if (_photoFile != null) ...[
              const SizedBox(height: 8),
              const Text('Photo will be uploaded.'),
            ],
          ],
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

      final uid = user.id;
      final df = DateFormat('yyyy-MM-dd');
      final dateStr = df.format(_date);
      final amount = double.parse(_amountCtrl.text);

      // 1) Insert ledger row (without attachment first)
      final inserted = await supabaseCall(() async {
        return await _sb
            .from('petty_cash_ledger')
            .insert({
              'date': dateStr, // DATE
              'amount': amount,
              'transaction_type': 'expense',
              'remarks': _notesCtrl.text.trim().isEmpty
                  ? null
                  : _notesCtrl.text.trim(),
              'attachment_path': null, // patch after upload
              'transaction_status': 'pending',
              'entered_by': _enteredBy,
              'approved_by': null,
              'creator_uuid': uid,
              'created_time': DateTime.now().toIso8601String(),
            })
            .select('id')
            .single();
      });

      final ledgerId = inserted['id'] as String;

      // 2) Optional: upload photo and patch attachment
      if (_photoFile != null) {
        // Use a key relative to the 'receipts' bucket (do not prefix with bucket name)
        final path = 'petty/$uid/$ledgerId-${const Uuid().v4()}.jpg';
        try {
          await supabaseCall(() async {
            return await _sb.storage.from('receipts').upload(path, _photoFile!);
          });
          await supabaseCall(() async {
            return await _sb
                .from('petty_cash_ledger')
                .update({'attachment_path': path}).eq('id', ledgerId);
          });
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Saved without photo (storage error): $e')),
          );
        }
      }

      if (!mounted) return;
      _snack('Bill submitted');
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack('DB error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to submit bill');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    final rs = ResponsiveSize.of(context);
    return InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs.radius(10)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs.radius(10)),
        borderSide: BorderSide(color: _green.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(rs.radius(10)),
        borderSide: BorderSide(color: _green, width: rs.w(1.6)),
      ),
      labelStyle: TextStyle(
          color: _green.withValues(alpha: 0.9), fontSize: rs.font(13)),
      contentPadding: EdgeInsets.symmetric(
        horizontal: rs.space(12),
        vertical: rs.space(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final df = DateFormat('yyyy-MM-dd');

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F7),
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: _gold),
        title: Text(
          'Submit Petty Cash Bill',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      body: SafeArea(
        minimum: EdgeInsets.all(rs.space(16)),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Date
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Date',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _green,
                    fontSize: rs.font(13),
                  ),
                ),
                subtitle: Text(
                  df.format(_date),
                  style: TextStyle(
                    color: _green.withValues(alpha: 0.85),
                    fontSize: rs.font(14),
                  ),
                ),
                trailing: IconButton(
                  icon:
                      Icon(Icons.date_range, color: _green, size: rs.icon(22)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
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
                decoration: _inputDecoration('Amount (₹)'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Amount is required';
                  }
                  final parsed = double.tryParse(v);
                  if (parsed == null) return 'Enter a valid number';
                  if (parsed <= 0) return 'Amount must be greater than zero';
                  return null;
                },
              ),
              SizedBox(height: rs.space(12)),

              // Notes (required for expense)
              TextFormField(
                controller: _notesCtrl,
                decoration: _inputDecoration('Notes (required)'),
                maxLines: 3,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Notes are required for expenses';
                  }
                  return null;
                },
              ),
              SizedBox(height: rs.space(12)),

              // Entered by (read-only)
              InputDecorator(
                decoration: _inputDecoration('Entered by'),
                child: Text(
                  _enteredBy,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _green,
                    fontSize: rs.font(14),
                  ),
                ),
              ),
              SizedBox(height: rs.space(12)),

              // Photo row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.camera),
                      icon: Icon(Icons.photo_camera_outlined,
                          color: _green, size: rs.icon(18)),
                      label: Text('Take Photo',
                          style: TextStyle(fontSize: rs.font(14))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: BorderSide(color: _green.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.radius(10)),
                        ),
                        padding: EdgeInsets.symmetric(vertical: rs.space(12)),
                      ),
                    ),
                  ),
                  SizedBox(width: rs.space(8)),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickPhoto(ImageSource.gallery),
                      icon: Icon(Icons.photo_library_outlined,
                          color: _green, size: rs.icon(18)),
                      label: Text('Pick from Gallery',
                          style: TextStyle(fontSize: rs.font(14))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _green,
                        side: BorderSide(color: _green.withValues(alpha: 0.45)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(rs.radius(10)),
                        ),
                        padding: EdgeInsets.symmetric(vertical: rs.space(12)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_photoFile != null) ...[
                SizedBox(height: rs.space(12)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(rs.radius(10)),
                  child: Image.file(
                    _photoFile!,
                    height: rs.h(160),
                    fit: BoxFit.cover,
                  ),
                ),
              ],
              SizedBox(height: rs.space(20)),

              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: _gold,
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.space(16),
                    vertical: rs.space(14),
                  ),
                  textStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: rs.font(14),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(rs.radius(12)),
                  ),
                ),
                child: _busy
                    ? SizedBox(
                        height: rs.icon(18),
                        width: rs.icon(18),
                        child: const CircularProgressIndicator(),
                      )
                    : const Text('Review & Confirm'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
