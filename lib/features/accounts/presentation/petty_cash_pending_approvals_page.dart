// lib/features/accounts/presentation/petty_cash_pending_approvals_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class PettyCashPendingApprovalsPage extends StatefulWidget {
  const PettyCashPendingApprovalsPage({super.key});

  @override
  State<PettyCashPendingApprovalsPage> createState() =>
      _PettyCashPendingApprovalsPageState();
}

// Emville theme colors
const Color _green = Color(0xFF103329);
const Color _gold = Color(0xFFD9A633);

class _PettyCashPendingApprovalsPageState
    extends State<PettyCashPendingApprovalsPage> {
  final _sb = Supabase.instance.client;

  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _resolveRole();
  }

  Future<void> _resolveRole() async {
    final uid = _sb.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await supabaseCall(() async {
        return await _sb
            .from('user_roles')
            .select('role')
            .eq('user_id', uid)
            .limit(1);
      });
      final role = rows.isNotEmpty ? rows.first['role'] as String? : null;
      setState(() => _isAdmin = role == 'owner' || role == 'admin');
    } catch (_) {
      setState(() => _isAdmin = false);
    }
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final builder = _sb.from('petty_cash_ledger').select(
          'id, date, amount, transaction_type, remarks, attachment_path, transaction_status, entered_by, approved_by, created_time',
        ) as PostgrestFilterBuilder;

    final rows = await builder
        .eq('transaction_status', 'pending')
        .order('date', ascending: true)
        .order('created_time', ascending: true);

    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<String> _resolveMyName() async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'User';
    final uid = user.id;

    try {
      final row1 = await supabaseCall(() async {
        return await _sb
            .from('users')
            .select('full_name, name, display_name')
            .eq('uid', uid)
            .maybeSingle();
      });
      final cand1 = (row1?['full_name'] ??
          row1?['name'] ??
          row1?['display_name']) as String?;
      if (cand1 != null && cand1.trim().isNotEmpty) return cand1.trim();

      final row2 = await supabaseCall(() async {
        return await _sb
            .from('users')
            .select('full_name, name, display_name')
            .eq('uid', uid) // ✅ use 'uid', not 'id'
            .maybeSingle();
      });
      final cand2 = (row2?['full_name'] ??
          row2?['name'] ??
          row2?['display_name']) as String?;
      if (cand2 != null && cand2.trim().isNotEmpty) return cand2.trim();

      final row3 = await supabaseCall(() async {
        return await _sb
            .from('users')
            .select('full_name, name, display_name')
            .eq('uid', uid) // ✅ correct PK column
            .maybeSingle();
      });
      final cand3 = (row3?['full_name'] ??
          row3?['name'] ??
          row3?['display_name']) as String?;
      if (cand3 != null && cand3.trim().isNotEmpty) return cand3.trim();
    } catch (_) {
      // ignore
    }

    final metaName = user.userMetadata?['name'] as String?;
    if (metaName != null && metaName.trim().isNotEmpty) return metaName.trim();

    final emailPrefix = user.email?.split('@').first;
    if (emailPrefix != null && emailPrefix.trim().isNotEmpty) {
      return emailPrefix.trim();
    }
    return 'User';
  }

  Future<String?> _signedUrl(String path) async {
    try {
      final url = await supabaseCall(() async {
        return await _sb.storage.from('receipts').createSignedUrl(path, 600);
      });
      return url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _approve(String id) async {
    if (!_isAdmin) return;
    final approver = await _resolveMyName();
    try {
      await supabaseCall(() async {
        return await _sb.from('petty_cash_ledger').update({
          'transaction_status': 'approved',
          'approved_by': approver,
        }).eq('id', id);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry approved')));
      setState(() {}); // refresh
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: ${e.message}')));
    }
  }

  Future<void> _delete(String id) async {
    if (!_isAdmin) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('Do you really want to delete this entry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _gold,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await supabaseCall(() async {
        return await _sb.from('petty_cash_ledger').delete().eq('id', id);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Entry deleted')));
      setState(() {}); // refresh
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Delete failed: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F7),
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: _gold),
        leading: const BackButton(color: _gold),
        title: Text(
          'Petty Cash Pending Approvals',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _load(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final data = snap.data ?? const [];
            if (data.isEmpty) {
              return Center(
                child: Text(
                  'No pending entries',
                  style: TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                    fontSize: rs.font(14),
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: EdgeInsets.all(rs.space(12)),
              itemCount: data.length,
              separatorBuilder: (_, __) => SizedBox(height: rs.space(8)),
              itemBuilder: (context, i) {
                final r = data[i];
                final id = r['id'] as String;
                final date = (r['date'] as String?) ??
                    (r['created_time'] as String? ?? '').split('T').first;
                final amount = (r['amount'] as num?)?.toDouble() ?? 0;
                final type = (r['transaction_type'] as String?) ?? 'expense';
                final remarks = r['remarks'] as String?;
                final attachmentPath = r['attachment_path'] as String?;
                final enteredBy = r['entered_by'] as String? ?? '—';

                final isIncome = type == 'income';
                final color = isIncome ? Colors.green : Colors.red;

                return Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(rs.radius(14)),
                    side: BorderSide(color: _green.withValues(alpha: 0.15)),
                  ),
                  elevation: 1.5,
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.symmetric(
                      horizontal: rs.space(16),
                      vertical: rs.space(4),
                    ),
                    leading: Icon(
                      isIncome
                          ? Icons.trending_up
                          : Icons.receipt_long_outlined,
                      color: color,
                      size: rs.icon(20),
                    ),
                    title: Text(
                      '₹${amount.toStringAsFixed(2)} • ${isIncome ? 'Income' : 'Expense'}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(15),
                      ),
                    ),
                    subtitle: Text(
                      '$date • by $enteredBy',
                      style: TextStyle(
                        color: _green.withValues(alpha: 0.75),
                        fontSize: rs.font(13),
                      ),
                    ),
                    children: [
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          rs.space(16),
                          0,
                          rs.space(16),
                          rs.space(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (remarks != null && remarks.trim().isNotEmpty)
                              Padding(
                                padding: EdgeInsets.only(bottom: rs.space(6)),
                                child: Text(
                                  'Notes: $remarks',
                                  style: TextStyle(
                                    color: _green,
                                    fontSize: rs.font(14),
                                  ),
                                ),
                              ),
                            FutureBuilder<String?>(
                              future: attachmentPath == null
                                  ? Future.value(null)
                                  : _signedUrl(attachmentPath),
                              builder: (context, imgSnap) {
                                final url = imgSnap.data;
                                if (url == null) {
                                  return const SizedBox.shrink();
                                }
                                return GestureDetector(
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        child: InteractiveViewer(
                                          child: Image.network(
                                            url,
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(rs.radius(8)),
                                    child: Image.network(
                                      url,
                                      height: rs.h(160),
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                );
                              },
                            ),
                            SizedBox(height: rs.space(12)),
                            Row(
                              children: [
                                if (_isAdmin)
                                  FilledButton(
                                    onPressed: () => _approve(id),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _green,
                                      foregroundColor: _gold,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: rs.space(14),
                                        vertical: rs.space(10),
                                      ),
                                      textStyle: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: rs.font(14),
                                      ),
                                    ),
                                    child: const Text('Approve'),
                                  ),
                                SizedBox(width: rs.space(8)),
                                if (_isAdmin)
                                  OutlinedButton.icon(
                                    onPressed: () => _delete(id),
                                    icon: Icon(
                                      Icons.delete_outline,
                                      size: rs.icon(18),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: _green,
                                      side: const BorderSide(color: _green),
                                      padding: EdgeInsets.symmetric(
                                        horizontal: rs.space(12),
                                        vertical: rs.space(10),
                                      ),
                                    ),
                                    label: Text(
                                      'Delete',
                                      style: TextStyle(fontSize: rs.font(14)),
                                    ),
                                  ),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => Navigator.maybePop(context),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _green,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: rs.space(8),
                                      vertical: rs.space(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Close',
                                    style: TextStyle(fontSize: rs.font(14)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
