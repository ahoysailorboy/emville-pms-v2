import '../data/finance_access.dart';
import 'account_balance_box.dart';
import 'package:emville_pms/ui/ledger_panel.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
// lib/features/accounts/presentation/main_accounts_page.dart
import 'dart:async';
//import 'package:emville_pms/services/role_service.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_income_receipt_form_page.dart';
import 'main_expenses_form_page.dart';
import 'main_salary_form_page.dart';
import 'main_accounts_pending_approvals_page.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class MainAccountsPage extends StatefulWidget {
  const MainAccountsPage({super.key});

  @override
  State<MainAccountsPage> createState() => _MainAccountsPageState();
}

class _MainAccountsPageState extends State<MainAccountsPage> {
  final _sb = Supabase.instance.client;

  bool _isAdmin = false;

  // Emville theme colors

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final allowed = await FinanceAccess.isOwnerOrAdmin(_sb);
    if (mounted) setState(() => _isAdmin = allowed);
  }

  Future<List<_LedgerRow>> _loadEntries() async {
    final privileged = await FinanceAccess.isOwnerOrAdmin(_sb);
    final from = DateTime.now()
        .subtract(const Duration(days: 90))
        .toIso8601String()
        .split('T')
        .first;

    // Build as FilterBuilder so we can chain .gte() before .order()
    var q = _sb.from('main_ledger').select(
          'id, date, amount, transaction_type, payee_payer_name, remarks, transaction_status, created_by, approved_by, attachment_path, payment_mode, created_time${privileged ? ",account_balance" : ""}',
        ) as PostgrestFilterBuilder;

    q = q.gte('date', from);

    // Finalize ordering right before awaiting
    final rows = await q
        .order('date', ascending: false)
        .order('created_time', ascending: false);

    return (rows as List).map<_LedgerRow>((r) {
      return _LedgerRow(
        id: r['id'] as String,
        date: (r['date'] as String?) ??
            (r['created_time'] as String? ?? '').split('T').first,
        amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
        type: (r['transaction_type'] as String?) ?? 'expense',
        status: (r['transaction_status'] as String?) ?? 'pending',
        payeePayer: r['payee_payer_name'] as String?,
        remarks: r['remarks'] as String?,
        createdBy: r['created_by'] as String?,
        approvedBy: r['approved_by'] as String?,
        attachmentPath: r['attachment_path'] as String?,
        paymentMode: r['payment_mode'] as String?,
        accountBalance: (r['account_balance'] as num?)?.toDouble(),
      );
    }).toList();
  }

  Future<_Balances> _loadBalances() async {
    if (!await FinanceAccess.isOwnerOrAdmin(_sb)) {
      return const _Balances(ledger: 0, approved: 0);
    }
    final rows = await supabaseCall(() async {
      return await _sb
          .from('main_ledger_balance')
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
        return await _sb.from('main_ledger').update({
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await supabaseCall(() async {
        return await _sb.from('main_ledger').delete().eq('id', id);
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

    final isApproved = row.status == 'approved';
    final isIncome = row.type == 'income';
    final color = isIncome ? Colors.green : Colors.red;

    final rs = ResponsiveSize.of(context);

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
              isIncome ? 'Income Receipt' : 'Payment',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: rs.font(18),
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: rs.space(6)),
            Text('Date: ${row.date}'),
            SizedBox(height: rs.space(4)),
            Text(
              'Amount: ₹${row.amount.toStringAsFixed(2)}',
              style: TextStyle(
                  fontFamily: 'Roboto',
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
            SizedBox(height: rs.space(4)),
            Text('Status: ${row.status}'),
            if (row.paymentMode != null && row.paymentMode!.isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Payment mode: ${row.paymentMode}'),
            ],
            if (row.payeePayer != null &&
                row.payeePayer!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Payee / Payer: ${row.payeePayer}'),
            ],
            if (row.createdBy != null && row.createdBy!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Created by: ${row.createdBy}'),
            ],
            if (row.approvedBy != null &&
                row.approvedBy!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Approved by: ${row.approvedBy}'),
            ],
            if (row.remarks != null && row.remarks!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Notes: ${row.remarks}'),
            ],
            if (_isAdmin && row.accountBalance != null) ...[
              SizedBox(height: rs.space(4)),
              Text(
                'Account balance (at entry): ₹${row.accountBalance!.toStringAsFixed(2)}',
              ),
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
                  borderRadius: BorderRadius.circular(rs.radius(8)),
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
                    child: const Text('Approve'),
                  ),
                  SizedBox(width: rs.space(8)),
                ],
                if (_isAdmin)
                  OutlinedButton.icon(
                    onPressed: () => _delete(row.id),
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
            SizedBox(height: rs.space(8)),
          ],
        ),
      ),
    );
  }

  // UPDATED: allow nullable onTap and an enabled flag
  @override
  Widget build(BuildContext context) => LedgerPanel(
        title: 'Main ledger',
        period: 'Last 90 days',
        onRefresh: _refresh,
        actions: [
          OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MainIncomeReceiptFormPage()));
                if (mounted) setState(() {});
              },
              child: const Text('Income receipt')),
          OutlinedButton(
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const MainExpensesFormPage()));
                if (mounted) setState(() {});
              },
              child: const Text('Payment receipt')),
          if (_isAdmin)
            OutlinedButton(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MainSalaryFormPage()));
                  if (mounted) setState(() {});
                },
                child: const Text('Salary receipt')),
          if (_isAdmin)
            OutlinedButton(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const MainAccountPendingApprovalsPage()));
                  if (mounted) setState(() {});
                },
                child: const Text('Pending approvals')),
        ],
        balance: !_isAdmin
            ? const SizedBox.shrink()
            : FutureBuilder<_Balances>(
                future: _loadBalances(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return EmvilleError(onRetry: _refresh);
                  return AccountBalanceBox(
                    label: 'Main ledger',
                    photo: true,
                    showUnapproved: _isAdmin,
                    balance: AccountBalance(
                        approved: snapshot.data?.approved,
                        ledger: snapshot.data?.ledger),
                  );
                }),
        entries: _loadEntries().then((rows) => rows
            .map((r) => LedgerEntry(
                title: r.remarks?.isNotEmpty == true
                    ? r.remarks!
                    : r.payeePayer?.isNotEmpty == true
                        ? r.payeePayer!
                        : (r.type == 'income' ? 'Income' : 'Expense'),
                description:
                    '${r.payeePayer ?? ''} · ${r.paymentMode ?? '—'} · ${shortDate(r.date)}',
                date: r.date,
                amount: r.amount,
                income: r.type == 'income',
                status: r.status,
                onTap: () => _showDetails(r)))
            .toList()),
      );
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
    this.payeePayer,
    this.remarks,
    this.createdBy,
    this.approvedBy,
    this.attachmentPath,
    this.paymentMode,
    this.accountBalance,
  });

  final String id;
  final String date; // yyyy-MM-dd
  final double amount;
  final String type;
  final String status;
  final String? payeePayer;
  final String? remarks;
  final String? createdBy;
  final String? approvedBy;
  final String? attachmentPath;
  final String? paymentMode;
  final double? accountBalance;
}
