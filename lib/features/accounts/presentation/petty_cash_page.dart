// lib/features/accounts/presentation/petty_cash_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'petty_cash_pending_approvals_page.dart';
import 'petty_cash_bill_form_page.dart';
import 'petty_cash_topup_form_page.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class PettyCashPage extends StatefulWidget {
  const PettyCashPage({super.key});

  @override
  State<PettyCashPage> createState() => _PettyCashPageState();
}

// Emville theme colors
const Color _green = Color(0xFF103329);
const Color _gold = Color(0xFFD9A633);

class _PettyCashPageState extends State<PettyCashPage> {
  final _sb = Supabase.instance.client;

  bool _isAdmin = false;
  final bool _showOnlyPending = false;

  // NEW: controller for the scrollable list in the middle
  final ScrollController _listScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRole() async {
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
      setState(() {
        _isAdmin = (role == 'owner' || role == 'admin');
      });
    } catch (_) {
      setState(() => _isAdmin = false);
    }
  }

  Future<List<_LedgerRow>> _loadLedger() async {
    final from = DateTime.now()
        .subtract(const Duration(days: 31))
        .toIso8601String()
        .split('T')
        .first;

    var q = _sb.from('petty_cash_ledger').select(
          'id, date, amount, transaction_type, remarks, attachment_path, transaction_status, entered_by, approved_by, created_time',
        ) as PostgrestFilterBuilder;

    q = q.gte('date', from);
    if (_showOnlyPending) {
      q = q.eq('transaction_status', 'pending');
    }

    final rows = await q
        .order('date', ascending: false)
        .order('created_time', ascending: false);

    return (rows as List).map<_LedgerRow>((r) {
      return _LedgerRow(
        id: r['id'] as String,
        date: (r['date'] as String?) ??
            (r['created_time'] as String? ?? '').split('T').first,
        amount: (r['amount'] as num?)?.toDouble() ?? 0,
        type: (r['transaction_type'] as String?) ?? 'expense',
        remarks: r['remarks'] as String?,
        attachmentPath: r['attachment_path'] as String?,
        status: (r['transaction_status'] as String?) ?? 'pending',
        enteredBy: r['entered_by'] as String?,
        approvedBy: r['approved_by'] as String?,
      );
    }).toList();
  }

  Future<_Balances> _loadBalances() async {
    final rows = await supabaseCall(() async {
      return await _sb
          .from('petty_cash_balance')
          .select('ledger_balance, approved_balance')
          .limit(1);
    });
    if (rows.isNotEmpty) {
      final m = rows.first;
      return _Balances(
        ledger: (m['ledger_balance'] as num?)?.toDouble() ?? 0.0,
        approved: (m['approved_balance'] as num?)?.toDouble() ?? 0.0,
      );
    }
    return const _Balances(ledger: 0, approved: 0);
  }

  Future<void> _refresh() async => setState(() {});

  Future<void> _approve(String id) async {
    try {
      final approverName = await _currentUserFullName();
      await supabaseCall(() async {
        return await _sb.from('petty_cash_ledger').update({
          'transaction_status': 'approved',
          'approved_by': approverName,
        }).eq('id', id);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Approved')));
      setState(() {});
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: ${e.message}')));
    }
  }

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text(
          'Do you really want to delete this entry? This cannot be undone.',
        ),
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
    if (ok != true) return;

    try {
      await supabaseCall(() async {
        return await _sb.from('petty_cash_ledger').delete().eq('id', id);
      });
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

  Future<String> _currentUserFullName() async {
    final user = _sb.auth.currentUser;
    if (user == null) return 'User';
    try {
      final row = await supabaseCall(() async {
        return await _sb
            .from('users')
            .select('full_name')
            .eq('uid', user.id)
            .maybeSingle();
      });
      final name = row?['full_name'] as String?;
      if (name != null && name.trim().isNotEmpty) return name.trim();
    } catch (_) {}
    final metaFull = user.userMetadata?['full_name'] as String?;
    final metaName = user.userMetadata?['name'] as String?;
    return (metaFull ?? metaName ?? user.email?.split('@').first ?? 'User')
        .trim();
  }

  Future<String?> _signedUrl(String path) async {
    try {
      return await supabaseCall(() async {
        return await _sb.storage
            .from('receipts')
            .createSignedUrl(path, 60 * 10);
      });
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

    final rs = ResponsiveSize.of(context);
    final isApproved = row.status == 'approved';
    final color = row.type == 'income' ? Colors.green : Colors.red;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          rs.space(16),
          rs.space(12),
          rs.space(16),
          rs.space(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.type == 'income' ? 'Top-up (Income)' : 'Bill (Expense)',
              style: TextStyle(
                fontSize: rs.font(18),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: rs.space(6)),
            Text('Date: ${row.date}', style: TextStyle(fontSize: rs.font(14))),
            SizedBox(height: rs.space(4)),
            Text(
              'Amount: ₹${row.amount.toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: rs.font(15),
              ),
            ),
            SizedBox(height: rs.space(4)),
            Text('Status: ${row.status}',
                style: TextStyle(fontSize: rs.font(14))),
            if (row.enteredBy != null && row.enteredBy!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Created by: ${row.enteredBy}',
                  style: TextStyle(fontSize: rs.font(14))),
            ],
            if (row.approvedBy != null &&
                row.approvedBy!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Approved by: ${row.approvedBy}',
                  style: TextStyle(fontSize: rs.font(14))),
            ],
            if (row.remarks != null && row.remarks!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Notes: ${row.remarks}',
                  style: TextStyle(fontSize: rs.font(14))),
            ],
            SizedBox(height: rs.space(12)),
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
                  borderRadius: BorderRadius.circular(rs.radius(10)),
                  child: Image.network(
                    imageUrl,
                    height: rs.h(160),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            SizedBox(height: rs.space(16)),
            Row(
              children: [
                if (_isAdmin && !isApproved) ...[
                  FilledButton(
                    onPressed: () => _approve(row.id),
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: _gold,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.radius(10)),
                      ),
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
                ],
                if (_isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => _delete(row.id),
                    icon: Icon(Icons.delete_outline, size: rs.icon(18)),
                    label:
                        Text('Delete', style: TextStyle(fontSize: rs.font(14))),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: BorderSide(color: _green.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(rs.radius(10)),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: rs.space(12),
                        vertical: rs.space(10),
                      ),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Close', style: TextStyle(fontSize: rs.font(14))),
                ),
              ],
            ),
            SizedBox(height: rs.space(8)),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    final rs = ResponsiveSize.of(context);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(rs.radius(12)),
      child: Container(
        height: rs.h(92),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(rs.radius(12)),
          color:
              enabled ? _green.withValues(alpha: 0.06) : Colors.grey.shade200,
          border: Border.all(
            color:
                enabled ? _green.withValues(alpha: 0.25) : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: enabled ? _green : Colors.grey,
                size: rs.icon(22),
              ),
              SizedBox(height: rs.space(6)),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: enabled ? _green : Colors.grey,
                  fontSize: rs.font(13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F7),
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: _gold),
        title: Text(
          'Petty Cash',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // TOP: fixed action tiles
            Padding(
              padding: EdgeInsets.fromLTRB(
                rs.space(12),
                rs.space(12),
                rs.space(12),
                rs.space(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _actionTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'Submit Bill',
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const PettyCashBillFormPage(),
                          ),
                        );
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(width: rs.space(8)),
                  Expanded(
                    child: _actionTile(
                      icon: Icons.add_card_outlined,
                      label: 'Top up',
                      onTap: _isAdmin
                          ? () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PettyCashTopupFormPage(),
                                ),
                              );
                              setState(() {});
                            }
                          : null,
                      enabled: _isAdmin,
                    ),
                  ),
                  SizedBox(width: rs.space(8)),
                  Expanded(
                    child: _actionTile(
                      icon: Icons.pending_actions_outlined,
                      label: 'Pending approvals',
                      onTap: _isAdmin
                          ? () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const PettyCashPendingApprovalsPage(),
                                ),
                              );
                              setState(() {});
                            }
                          : null,
                      enabled: _isAdmin,
                    ),
                  ),
                ],
              ),
            ),

            // MIDDLE: ONLY this list scrolls (with scrollbar)
            Expanded(
              child: FutureBuilder<List<_LedgerRow>>(
                future: _loadLedger(),
                builder: (context, snap) {
                  final loading = snap.connectionState != ConnectionState.done;
                  final rows = snap.data ?? const <_LedgerRow>[];

                  if (loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (rows.isEmpty) {
                    return const Center(
                      child: Text('No activity in last 31 days'),
                    );
                  }

                  return RefreshIndicator(
                    color: _green,
                    onRefresh: _refresh,
                    child: Scrollbar(
                      controller: _listScrollCtrl,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _listScrollCtrl,
                        padding: EdgeInsets.symmetric(
                          horizontal: rs.space(12),
                          vertical: rs.space(4),
                        ),
                        itemCount: rows.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: rs.space(8)),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          final isIncome = r.type == 'income';
                          final color = isIncome ? Colors.green : Colors.red;
                          final title = isIncome ? 'Top-up' : 'Bill';
                          return Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(rs.radius(14)),
                              side: BorderSide(
                                  color: _green.withValues(alpha: 0.15)),
                            ),
                            child: ListTile(
                              onTap: () => _showDetails(r),
                              leading: Container(
                                height: rs.h(40),
                                width: rs.w(40),
                                decoration: BoxDecoration(
                                  color: _green.withValues(alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(rs.radius(10)),
                                ),
                                child: Icon(
                                  isIncome
                                      ? Icons.trending_up
                                      : Icons.receipt_long_outlined,
                                  color: color,
                                  size: rs.icon(20),
                                ),
                              ),
                              title: Text(
                                '$title • ₹${r.amount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: rs.font(15),
                                ),
                              ),
                              subtitle: Text(
                                '${r.date}'
                                '${(r.remarks == null || r.remarks!.isEmpty) ? '' : ' • ${r.remarks}'}'
                                '${_isAdmin ? ' • ${r.status}' : ''}',
                                style: TextStyle(
                                  color: _green.withValues(alpha: 0.75),
                                  fontSize: rs.font(13),
                                ),
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: _green,
                                size: rs.icon(18),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            // BOTTOM: fixed balance tiles
            Padding(
              padding: EdgeInsets.fromLTRB(
                rs.space(12),
                rs.space(8),
                rs.space(12),
                rs.space(12),
              ),
              child: FutureBuilder<_Balances>(
                future: _loadBalances(),
                builder: (context, balSnap) {
                  final b =
                      balSnap.data ?? const _Balances(ledger: 0, approved: 0);
                  return Row(
                    children: [
                      Expanded(
                        child: _balanceTile(
                          title: 'Ledger balance',
                          amount: b.ledger,
                        ),
                      ),
                      SizedBox(width: rs.space(8)),
                      Expanded(
                        child: _balanceTile(
                          title: 'Approved balance',
                          amount: b.approved,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _balanceTile({required String title, required double amount}) {
    final rs = ResponsiveSize.of(context);
    final amountColor = amount >= 0 ? Colors.green : Colors.red;
    return Container(
      height: rs.h(92),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(rs.radius(12)),
        color: _green.withValues(alpha: 0.06),
        border: Border.all(color: _green.withValues(alpha: 0.2)),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _green,
                fontSize: rs.font(13),
              ),
            ),
            SizedBox(height: rs.space(6)),
            Text(
              '₹${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: rs.font(18),
                fontWeight: FontWeight.w800,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Balances {
  const _Balances({required this.ledger, required this.approved});
  final double ledger;
  final double approved;
}

class _LedgerRow {
  _LedgerRow({
    required this.id,
    required this.date,
    required this.amount,
    required this.type, // 'income' | 'expense'
    required this.status, // 'pending' | 'approved'
    this.remarks,
    this.attachmentPath,
    this.enteredBy,
    this.approvedBy,
  });

  final String id;
  final String date; // yyyy-MM-dd
  final double amount;
  final String type;
  final String status;
  final String? remarks;
  final String? attachmentPath;
  final String? enteredBy;
  final String? approvedBy;
}
