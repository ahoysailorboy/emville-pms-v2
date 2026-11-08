import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/accounts/domain/income_receipt.dart';

class IncomeReceiptsRepo {
  final _sb = Supabase.instance.client;

  /// Fetch all income receipts
  Future<List<IncomeReceipt>> listIncomeReceipts() async {
    final res = await _sb
        .from('income_receipts')
        .select()
        .order('date', ascending: false);
    return (res as List)
        .map((row) => IncomeReceipt.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Add a new receipt
  Future<void> addIncomeReceipt(IncomeReceipt r) async {
    await _sb.from('income_receipts').insert(r.toJson());
  }

  /// Delete a receipt (admins only, RLS will enforce)
  Future<void> deleteIncomeReceipt(String id) async {
    await _sb.from('income_receipts').delete().eq('id', id);
  }
}
