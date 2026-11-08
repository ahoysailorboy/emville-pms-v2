// lib/features/accounts/presentation/petty_cash_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'petty_cash_bill_form_page.dart';
import 'petty_cash_topup_form_page.dart';

class PettyCashPage extends StatefulWidget {
  const PettyCashPage({super.key});

  @override
  State<PettyCashPage> createState() => _PettyCashPageState();
}

class _PettyCashPageState extends State<PettyCashPage> {
  final _sb = Supabase.instance.client;

  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _sb
          .from('user_roles')
          .select('role')
          .eq('user_id', uid)
          .limit(1);
      final role = rows.isNotEmpty ? rows.first['role'] as String? : null;
      setState(() => _isAdmin = (role == 'owner' || role == 'admin'));
    } catch (_) {
      setState(() => _isAdmin = false);
    }
  }

  Future<List<_LedgerRow>> _loadLedger() async {
    final from = DateTime.now()
        .subtract(const Duration(days: 30))
        .toIso8601String()
        .split('T')
        .first;

    // Petty cash bills (expenses from petty cash)
    final entries = await _sb
        .from('petty_cash_entries')
        .select(
          'id, date, amount, note, attachment_path, approved_at, created_at',
        )
        .gte('created_at', '${from}T00:00:00')
        .order('created_at', ascending: false);

    // Top-ups
    final topups = await _sb
        .from('petty_cash_topups')
        .select('id, date, amount, note, created_at')
        .gte('created_at', '${from}T00:00:00')
        .order('created_at', ascending: false);

    final list = <_LedgerRow>[];

    for (final r in (entries as List)) {
      final String? d = (r['date'] as String?) ?? (r['created_at'] as String?);
      list.add(
        _LedgerRow(
          id: r['id'] as String,
          kind: _Kind.entry,
          dateIso: d,
          amount: (r['amount'] as num?)?.toDouble() ?? 0,
          note: r['note'] as String?,
          attachmentPath: r['attachment_path'] as String?,
          approvedAt: r['approved_at'] as String?,
        ),
      );
    }

    for (final r in (topups as List)) {
      final String? d = (r['date'] as String?) ?? (r['created_at'] as String?);
      list.add(
        _LedgerRow(
          id: r['id'] as String,
          kind: _Kind.topup,
          dateIso: d,
          amount: (r['amount'] as num?)?.toDouble() ?? 0,
          note: r['note'] as String?,
        ),
      );
    }

    // Newest first
    list.sort((a, b) => b.dateStr.compareTo(a.dateStr));
    return list;
  }

  Future<double> _loadBalance() async {
    try {
      final from = DateTime.now()
          .subtract(const Duration(days: 30))
          .toIso8601String()
          .split('T')
          .first;

      // Only APPROVED entries reduce balance
      final entries = await _sb
          .from('petty_cash_entries')
          .select('amount')
          .gte('created_at', '${from}T00:00:00')
          .not('approved_at', 'is', null);

      final topups = await _sb
          .from('petty_cash_topups')
          .select('amount')
          .gte('created_at', '${from}T00:00:00');

      double spent = 0;
      for (final r in (entries as List)) {
        spent += (r['amount'] as num?)?.toDouble() ?? 0;
      }
      double added = 0;
      for (final r in (topups as List)) {
        added += (r['amount'] as num?)?.toDouble() ?? 0;
      }
      return added - spent;
    } catch (_) {
      // On any error show 0 but still render the row
      return 0;
    }
  }

  Future<void> _refresh() async => setState(() {});

  Future<void> _approveEntry(String id) async {
    try {
      await _sb
          .from('petty_cash_entries')
          .update({'approved_at': DateTime.now().toIso8601String()})
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry approved')));
      setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: ${e.message}')));
    }
  }

  Future<void> _deleteRow(_Kind kind, String id) async {
    try {
      await _sb
          .from(
            kind == _Kind.entry ? 'petty_cash_entries' : 'petty_cash_topups',
          )
          .delete()
          .eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted')));
      setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: ${e.message}')));
    }
  }

  Future<String?> _signedUrl(String path) async {
    try {
      return await _sb.storage.from('receipts').createSignedUrl(path, 60 * 10);
    } catch (_) {
      return null;
    }
  }

  void _showDetails(_LedgerRow row) async {
    String? imageUrl;
    if (row.attachmentPath != null) {
      imageUrl = await _signedUrl(row.attachmentPath!);
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) {
        final isApproved = row.approvedAt != null;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.kind == _Kind.entry ? 'Petty Cash Bill' : 'Top-up',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              Text('Date: ${row.dateStr}'),
              const SizedBox(height: 4),
              Text('Amount: ₹${row.amount.toStringAsFixed(2)}'),
              if (row.note != null && row.note!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Note: ${row.note}'),
              ],
              if (row.kind == _Kind.entry) ...[
                const SizedBox(height: 4),
                Text('Status: ${isApproved ? 'approved' : 'pending'}'),
              ],
              const SizedBox(height: 12),
              if (imageUrl != null)
                GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(
                          child: Image.network(imageUrl!, fit: BoxFit.contain),
                        ),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      imageUrl,
                      height: 160,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_isAdmin && row.kind == _Kind.entry && !isApproved) ...[
                    FilledButton(
                      onPressed: () => _approveEntry(row.id),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (_isAdmin)
                    OutlinedButton.icon(
                      onPressed: () => _deleteRow(row.kind, row.id),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Petty Cash'),
        actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'Top up petty cash',
              icon: const Icon(Icons.add_card),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const PettyCashTopupFormPage(),
                  ),
                );
                setState(() {}); // refresh after returning
              },
            ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<_LedgerRow>>(
            future: _loadLedger(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data ?? const <_LedgerRow>[];

              return Column(
                children: [
                  Expanded(
                    child: rows.isEmpty
                        ? const Center(
                            child: Text(
                              'No petty cash activity in last 30 days',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: rows.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final r = rows[i];
                              final isTopup = r.kind == _Kind.topup;
                              final color = isTopup ? Colors.green : Colors.red;
                              final title = isTopup ? 'Top-up' : 'Bill';
                              return Card(
                                child: ListTile(
                                  onTap: () => _showDetails(r),
                                  leading: Icon(
                                    isTopup
                                        ? Icons.trending_up
                                        : Icons.receipt_long_outlined,
                                    color: color,
                                  ),
                                  title: Text(
                                    '$title • ₹${r.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${r.dateStr}${(r.note == null || r.note!.isEmpty) ? '' : ' • ${r.note}'}',
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                ),
                              );
                            },
                          ),
                  ),
                  // Balance footer (always shows; shows 0 on error)
                  FutureBuilder<double>(
                    future: _loadBalance(),
                    builder: (context, balSnap) {
                      final bal = balSnap.data ?? 0;
                      final balColor = bal >= 0 ? Colors.green : Colors.red;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Row(
                          children: [
                            const Text(
                              'Balance in hand',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '₹${bal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: balColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const PettyCashBillFormPage()),
          );
          setState(() {}); // refresh after adding
        },
        icon: const Icon(Icons.add),
        label: const Text('Add bill'),
      ),
    );
  }
}

enum _Kind { entry, topup }

class _LedgerRow {
  _LedgerRow({
    required this.id,
    required this.kind,
    required this.dateIso,
    required this.amount,
    this.note,
    this.attachmentPath,
    this.approvedAt,
  });

  final String id;
  final _Kind kind;
  final String? dateIso; // ISO yyyy-MM-dd or created_at
  final double amount;
  final String? note;
  final String? attachmentPath;
  final String? approvedAt;

  String get dateStr {
    final d = dateIso ?? '';
    // show date only even if it's a timestamp
    return d.split('T').first;
  }
}
