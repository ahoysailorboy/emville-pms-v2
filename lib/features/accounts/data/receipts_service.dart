// lib/features/accounts/data/receipts_service.dart
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// Simple model (expand later as needed)
class IncomeReceipt {
  final String id; // uuid
  final DateTime date;
  final double amount;
  final String payerName;
  final String? description;
  final String createdBy; // auth uid
  final String status; // 'pending' | 'approved' | 'rejected'

  IncomeReceipt({
    required this.id,
    required this.date,
    required this.amount,
    required this.payerName,
    required this.createdBy,
    required this.status,
    this.description,
  });

  factory IncomeReceipt.fromMap(Map<String, dynamic> m) => IncomeReceipt(
    id: m['id'] as String,
    date: DateTime.parse(m['date'] as String),
    amount: (m['amount'] as num).toDouble(),
    payerName: m['payer_name'] as String,
    description: m['description'] as String?,
    createdBy: m['created_by'] as String,
    status: m['status'] as String,
  );
}

/// Create a new income receipt (any signed-in user can insert; RLS handles it)
Future<String> createIncomeReceipt({
  required DateTime date,
  required double amount,
  required String payerName,
  String? description,
}) async {
  try {
    final res = await _sb
        .from('income_receipts')
        .insert({
          'date': date.toIso8601String(),
          'amount': amount,
          'payer_name': payerName,
          'description': description,
        })
        .select('id')
        .single();

    return res['id'] as String;
  } on PostgrestException catch (e) {
    log('[receipts] insert failed: ${e.code} ${e.message}');
    rethrow;
  } catch (e) {
    log('[receipts] insert failed: $e');
    rethrow;
  }
}

/// List receipts (optionally only “mine”)
Future<List<IncomeReceipt>> listIncomeReceipts({bool onlyMine = false}) async {
  final uid = _sb.auth.currentUser?.id;
  const cols = 'id, date, amount, payer_name, description, created_by, status';

  final rows = (onlyMine && uid != null)
      ? await _sb
            .from('income_receipts')
            .select(cols)
            .eq('created_by', uid) // filter first
            .order('date', ascending: false) // then order
      : await _sb
            .from('income_receipts')
            .select(cols)
            .order('date', ascending: false);

  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map(IncomeReceipt.fromMap)
      .toList();
}

/// Delete a receipt by id (RLS: only admin/owner OR creator-before-approval)
Future<void> deleteIncomeReceipt(String id) async {
  try {
    await _sb.from('income_receipts').delete().eq('id', id);
  } on PostgrestException catch (e) {
    log('[receipts] delete failed: ${e.code} ${e.message}');
    rethrow;
  } catch (e) {
    log('[receipts] delete failed: $e');
    rethrow;
  }
}
