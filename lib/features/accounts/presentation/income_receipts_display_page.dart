import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main_income_receipt_form_page.dart';

class IncomeReceiptsDisplayPage extends StatefulWidget {
  const IncomeReceiptsDisplayPage({super.key});

  @override
  State<IncomeReceiptsDisplayPage> createState() =>
      _IncomeReceiptsDisplayPageState();
}

class _IncomeReceiptsDisplayPageState extends State<IncomeReceiptsDisplayPage> {
  final _sb = Supabase.instance.client;
  final _df = DateFormat('yyyy-MM-dd');

  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _detectAdmin();
  }

  Future<void> _detectAdmin() async {
    try {
      final res = await _sb.rpc('is_admin');
      setState(() => _isAdmin = (res == true));
    } catch (_) {
      setState(() => _isAdmin = false);
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final fromDate = _df.format(
      DateTime.now().subtract(const Duration(days: 30)),
    );
    final rows = await _sb
        .from('income_receipts')
        .select(
          'id, date, amount, payer_name, notes, payment_type, attachment_path',
        )
        .gte('date', fromDate)
        .order('date', ascending: false);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<void> _refresh() async => setState(() {});

  String _fmtDate(String? ymdOrIso) => (ymdOrIso == null || ymdOrIso.isEmpty)
      ? '—'
      : (ymdOrIso.contains('T') ? ymdOrIso.split('T').first : ymdOrIso);

  String _fmtAmt(num? n) => '₹${(n ?? 0).toStringAsFixed(2)}';

  Future<String?> _signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await _sb.storage.from('receipts').createSignedUrl(path, 900);
    } catch (_) {
      return null;
    }
  }

  Future<void> _delete(String id) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete receipt'),
        content: const Text('Are you sure you want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await _sb.from('income_receipts').delete().eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Receipt deleted')));
      setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Delete failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Income Receipts')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _load(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snap.data ?? const [];
              if (data.isEmpty) {
                return const Center(
                  child: Text('No income in the last 30 days'),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: data.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) {
                  final r = data[i];
                  final id = r['id'] as String;
                  final date = _fmtDate(r['date'] as String?);
                  final amount = r['amount'] as num?;
                  final payer = (r['payer_name'] as String?) ?? '—';
                  final notes = r['notes'] as String?;
                  final payType = (r['payment_type'] as String?) ?? 'other';
                  final attach = r['attachment_path'] as String?;

                  return Card(
                    child: ExpansionTile(
                      title: Text('$payer • ${_fmtAmt(amount)}'),
                      subtitle: Text('Date: $date • Type: $payType'),
                      trailing: _isAdmin
                          ? IconButton(
                              tooltip: 'Delete',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(id),
                            )
                          : null,
                      children: [
                        if (notes != null && notes.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(notes),
                            ),
                          ),
                        if (attach != null && attach.isNotEmpty)
                          FutureBuilder<String?>(
                            future: _signedUrl(attach),
                            builder: (context, s) {
                              final url = s.data;
                              if (s.connectionState != ConnectionState.done) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    height: 80,
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  ),
                                );
                              }
                              if (url == null) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('No preview available'),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                child: InkWell(
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (_) => Dialog(
                                      child: InteractiveViewer(
                                        child: Image.network(url),
                                      ),
                                    ),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      url,
                                      height: 120,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const MainIncomeReceiptFormPage(),
            ),
          );
          setState(() {}); // refresh after returning from form
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Income'),
      ),
    );
  }
}
