// lib/features/accounts/presentation/petty_cash_topup_form_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class PettyCashTopupFormPage extends StatefulWidget {
  const PettyCashTopupFormPage({super.key});

  @override
  State<PettyCashTopupFormPage> createState() => _PettyCashTopupFormPageState();
}

// Emville theme
const Color _green = Color(0xFF103329);
const Color _gold = Color(0xFFD9A633);

class _PettyCashTopupFormPageState extends State<PettyCashTopupFormPage> {
  final _sb = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  DateTime _date = DateTime.now();
  final _amountCtrl = TextEditingController();

  String _addedBy = 'User'; // resolved on init
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _resolveAddedBy();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveAddedBy() async {
    final user = _sb.auth.currentUser;
    String name = 'User';

    if (user != null) {
      final uid = user.id;

      try {
        // users table uses "uid"
        final row = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('full_name')
              .eq('uid', uid)
              .maybeSingle();
        });

        final dbName = row?['full_name'] as String?;
        if (dbName != null && dbName.trim().isNotEmpty) {
          name = dbName.trim();
        } else {
          // fallback to auth metadata, then email prefix
          final metaName = (user.userMetadata?['full_name'] ??
              user.userMetadata?['name']) as String?;
          if (metaName != null && metaName.trim().isNotEmpty) {
            name = metaName.trim();
          } else {
            final emailPrefix = user.email?.split('@').first;
            if (emailPrefix != null && emailPrefix.trim().isNotEmpty) {
              name = emailPrefix.trim();
            }
          }
        }
      } catch (_) {
        final metaName = (user.userMetadata?['full_name'] ??
            user.userMetadata?['name']) as String?;
        if (metaName != null && metaName.trim().isNotEmpty) {
          name = metaName.trim();
        } else {
          name = user.email?.split('@').first ?? 'User';
        }
      }
    }

    if (mounted) setState(() => _addedBy = name);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final df = DateFormat('yyyy-MM-dd');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Top-up'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date: ${df.format(_date)}'),
            Text('Amount: ₹${_amountCtrl.text}'),
            Text('Added by: $_addedBy'),
            const Text('Status: pending'),
            const SizedBox(height: 8),
            const Text('This will be recorded as:'),
            const Text('• Transaction type: income'),
            const Text('• Remarks: Petty cash top-up'),
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

    if (confirm == true) {
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

      // Insert a PENDING income row (approve later in petty_cash_page)
      await supabaseCall(() async {
        return await _sb.from('petty_cash_ledger').insert({
          'date': dateStr,
          'amount': amount,
          'transaction_type': 'income',
          'remarks': 'Petty cash top-up',
          'attachment_path': null,
          'transaction_status': 'pending',
          'entered_by': _addedBy,
          'approved_by': null,
          'creator_uuid': uid,
          'created_time': DateTime.now().toIso8601String(),
        });
      });

      if (!mounted) return;
      _snack('Top-up submitted (pending approval)');
      Navigator.pop(context);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack('DB error: ${e.message}');
    } catch (e) {
      if (!mounted) return;
      _snack('Failed to add top-up');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _green.withValues(alpha: 0.35)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: _green, width: 1.6),
      ),
      labelStyle: TextStyle(color: _green.withValues(alpha: 0.9)),
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
          'Petty Cash Top-up',
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
                    fontSize: rs.font(14),
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
                      Icon(Icons.date_range, color: _green, size: rs.icon(20)),
                  onPressed: _pickDate,
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
                style: TextStyle(fontSize: rs.font(14)),
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

              // Added by (read-only)
              InputDecorator(
                decoration: _inputDecoration('Added by'),
                child: Text(
                  _addedBy,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _green,
                    fontSize: rs.font(14),
                  ),
                ),
              ),
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
                ),
                child: _busy
                    ? SizedBox(
                        height: rs.h(18),
                        width: rs.w(18),
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
