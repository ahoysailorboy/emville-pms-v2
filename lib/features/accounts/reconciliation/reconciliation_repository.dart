import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class BankReconciliationRepository {
  BankReconciliationRepository(this.client);
  final SupabaseClient client;
  Future<List<Map<String, dynamic>>> months() async =>
      List<Map<String, dynamic>>.from(await client
          .from('bank_reconciliations')
          .select()
          .neq('status', 'archived')
          .order('month', ascending: false));
  Future<Map<String, dynamic>> detail(String id) async {
    final session = await client
        .from('bank_reconciliations')
        .select()
        .eq('id', id)
        .single();
    final month = DateTime.parse(session['month']);
    final end = DateTime(month.year, month.month + 1);
    final result = await Future.wait([
      _rows('bank_statement_lines',
          column: 'reconciliation_id', value: id, order: 'line_number'),
      _rows('bank_reconciliation_proposals',
          select: '*,bank_statement_lines!inner(reconciliation_id)',
          column: 'bank_statement_lines.reconciliation_id',
          value: id),
      _rows('bank_reconciliation_links',
          select: '*,bank_statement_lines!inner(reconciliation_id)',
          column: 'bank_statement_lines.reconciliation_id',
          value: id),
      _ledger(month.subtract(const Duration(days: 31)),
          end.add(const Duration(days: 31))),
      _rows('bank_ledger_reviews', column: 'reconciliation_id', value: id),
      _rows('bank_reconciliation_notes',
          column: 'reconciliation_id',
          value: id,
          order: 'created_at',
          ascending: false),
      _rows('bank_ledger_reversal_proposals',
          column: 'reconciliation_id', value: id),
      _rows('bank_reconciliation_links', select: 'ledger_id'),
      Future<dynamic>(() async => await client.rpc('reminder_people')),
    ]);
    return {
      'session': session,
      'lines': result[0],
      'proposals': result[1],
      'links': result[2],
      'ledger': result[3],
      'reviews': result[4],
      'notes': result[5],
      'reversals': result[6],
      'globalLinks': result[7],
      'people': result[8]
    };
  }

  Future<List<Map<String, dynamic>>> _rows(String table,
      {String select = '*',
      String? column,
      String? value,
      String order = 'id',
      bool ascending = true}) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 500) {
      var q = client.from(table).select(select);
      if (column != null) q = q.eq(column, value!);
      final rows = await q
          .order(order, ascending: ascending)
          .order('id')
          .range(offset, offset + 499);
      result.addAll(List<Map<String, dynamic>>.from(rows));
      if (rows.length < 500) return result;
    }
  }

  Future<List<Map<String, dynamic>>> _ledger(
      DateTime start, DateTime end) async {
    final result = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 500) {
      final rows = await client
          .from('main_ledger')
          .select()
          .gte('date', start.toIso8601String().split('T').first)
          .lt('date', end.toIso8601String().split('T').first)
          .order('date')
          .order('id')
          .range(offset, offset + 499);
      result.addAll(List<Map<String, dynamic>>.from(rows));
      if (rows.length < 500) return result;
    }
  }

  Future<void> compare(String id) =>
      client.rpc('compare_bank_reconciliation', params: {'p_id': id});
  Future<void> resolve(String id, String action, String note,
          {String? ledger}) =>
      client.rpc('resolve_bank_line', params: {
        'p_line': id,
        'p_action': action,
        'p_note': note,
        'p_ledger': ledger
      });
  Future<void> approve(String id, String note, String payee) async {
    await client.rpc('approve_bank_proposal',
        params: {'p_proposal': id, 'p_note': note, 'p_payee': payee});
    unawaited(_notify());
  }

  Future<void> _notify() async {
    try {
      await client.functions.invoke('task_notifications');
    } catch (_) {}
  }

  Future<void> reviewLedger(
          String id, String ledger, String classification, String note) =>
      client.rpc('review_unmatched_bank_ledger', params: {
        'p_id': id,
        'p_ledger': ledger,
        'p_classification': classification,
        'p_note': note
      });
  Future<void> proposeDistinct(String line, String note) =>
      client.rpc('propose_distinct_bank_entry',
          params: {'p_line': line, 'p_note': note});
  Future<void> approveReversal(String proposal, String note) =>
      client.rpc('approve_bank_ledger_reversal',
          params: {'p_proposal': proposal, 'p_note': note});
  Future<void> discard(String id, String note) => client
      .rpc('discard_bank_reconciliation', params: {'p_id': id, 'p_note': note});
  Future<void> complete(String id, bool complete) =>
      client.rpc('set_bank_reconciliation_status',
          params: {'p_id': id, 'p_complete': complete});
}
