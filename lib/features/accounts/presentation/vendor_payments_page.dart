import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_expenses_form_page.dart';

class VendorPaymentsPage extends StatefulWidget {
  const VendorPaymentsPage({super.key});

  @override
  State<VendorPaymentsPage> createState() => _VendorPaymentsPageState();
}

class _VendorPaymentsPageState extends State<VendorPaymentsPage> {
  final _sb = Supabase.instance.client;
  final _df = DateFormat('yyyy-MM-dd');

  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _checkIsAdmin();
  }

  Future<void> _checkIsAdmin() async {
    try {
      final res = await _sb.rpc('is_admin'); // returns bool
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
        .from('expenses')
        .select(
          'id, date, amount, vendor_name, notes, payment_type, status, created_at, attachment_path',
        )
        .gte('date', fromDate)
        .order('date', ascending: false)
        .order('created_at', ascending: false);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<String?> _signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      // 15 minutes
      return await _sb.storage.from('receipts').createSignedUrl(path, 900);
    } catch (_) {
      return null;
    }
  }

  Future<void> _approve(String id) async {
    try {
      await _sb.from('expenses').update({'status': 'approved'}).eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry approved')));
      setState(() {}); // refresh list
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Approve failed')));
    }
  }

  Future<void> _delete(String id) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete payment'),
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
      await _sb.from('expenses').delete().eq('id', id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry deleted')));
      setState(() {}); // refresh list
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

  Future<void> _refresh() async => setState(() {});

  String _fmtDate(String? isoOrYmd) => (isoOrYmd == null || isoOrYmd.isEmpty)
      ? '—'
      : (isoOrYmd.contains('T') ? isoOrYmd.split('T').first : isoOrYmd);

  String _fmtAmt(num? n) => '₹${(n ?? 0).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vendor Payments')),
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
                  child: Text('No payments in the last 30 days'),
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
                  final amount = _fmtAmt((r['amount'] as num?)?.toDouble());
                  final vendor = r['vendor_name'] as String? ?? '—';
                  final status = (r['status'] as String?) ?? 'pending';
                  final payType = (r['payment_type'] as String?) ?? 'other';
                  final notes = r['notes'] as String?;
                  final path = r['attachment_path'] as String?;

                  return Card(
                    child: ExpansionTile(
                      title: Text('$vendor • $amount'),
                      subtitle: Text(
                        'Date: $date • Type: ${payType.replaceAll('_', ' ')}',
                      ),
                      childrenPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      children: [
                        _row('Status', status),
                        if (notes != null && notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 6),
                          _row('Notes', notes),
                        ],
                        const SizedBox(height: 12),
                        if (path != null && path.isNotEmpty)
                          FutureBuilder<String?>(
                            future: _signedUrl(path),
                            builder: (context, s) {
                              if (s.connectionState != ConnectionState.done) {
                                return const SizedBox(
                                  height: 64,
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final url = s.data;
                              if (url == null) {
                                return const Text(
                                  'Receipt image unavailable',
                                  style: TextStyle(color: Colors.black54),
                                );
                              }
                              return GestureDetector(
                                onTap: () => showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.contain,
                                      ),
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
                              );
                            },
                          ),
                        const SizedBox(height: 12),
                        if (_isAdmin)
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: () => _approve(id),
                                icon: const Icon(Icons.check_circle_outline),
                                label: const Text('Approve'),
                              ),
                              const SizedBox(width: 12),
                              TextButton.icon(
                                onPressed: () => _delete(id),
                                icon: const Icon(Icons.delete_outline),
                                label: const Text('Delete'),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                              ),
                            ],
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
            MaterialPageRoute(builder: (_) => const MainExpensesFormPage()),
          );
          setState(() {}); // reload after returning from form
        },
        icon: const Icon(Icons.add),
        label: const Text('Add Payment'),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(k, style: const TextStyle(color: Colors.black54)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(v)),
      ],
    );
  }
}
