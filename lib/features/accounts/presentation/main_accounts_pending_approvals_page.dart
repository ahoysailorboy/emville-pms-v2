// lib/features/accounts/presentation/main_account_pending_approvals_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class MainAccountPendingApprovalsPage extends StatefulWidget {
  const MainAccountPendingApprovalsPage({super.key});

  @override
  State<MainAccountPendingApprovalsPage> createState() =>
      _MainAccountPendingApprovalsPageState();
}

// Emville theme colors
const Color _green = Color(0xFF103329);
const Color _gold = Color(0xFFD9A633);

class _MainAccountPendingApprovalsPageState
    extends State<MainAccountPendingApprovalsPage> {
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
      final rows = await supabaseCall(() async {
        return await _sb
            .from('user_roles')
            .select('role')
            .eq('user_id', uid)
            .limit(1);
      });
      final role = rows.isNotEmpty ? rows.first['role'] as String? : null;
      setState(() {
        _isAdmin =
            (role == 'owner' || role == 'admin' || role == 'super_admin');
      });
    } catch (_) {
      setState(() => _isAdmin = false);
    }
  }

  Future<List<_PendingRow>> _loadPending() async {
    // Build as FilterBuilder so we can chain filters before order()
    var q = _sb.from('main_ledger').select(
          'id, date, amount, transaction_type, payee_payer_name, remarks, transaction_status, created_by, approved_by, attachment_path, payment_mode, created_time',
        ) as PostgrestFilterBuilder;

    q = q.eq('transaction_status', 'pending');

    final rows = await q
        .order('date', ascending: true)
        .order('created_time', ascending: true);

    return (rows as List).map<_PendingRow>((r) {
      return _PendingRow(
        id: r['id'] as String,
        date: (r['date'] as String?) ??
            (r['created_time'] as String? ?? '').split('T').first,
        amount: (r['amount'] as num?)?.toDouble() ?? 0.0,
        type: (r['transaction_type'] as String?) ?? 'expense',
        payeePayer: r['payee_payer_name'] as String?,
        remarks: r['remarks'] as String?,
        createdBy: r['created_by'] as String?,
        attachmentPath: r['attachment_path'] as String?,
        paymentMode: r['payment_mode'] as String?,
      );
    }).toList();
  }

  Future<void> _refresh() async => setState(() {});

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

  Future<void> _approve(String id) async {
    if (!_isAdmin) return;
    try {
      final approver = await _currentUserFullName();
      await supabaseCall(() async {
        return await _sb.from('main_ledger').update({
          'transaction_status': 'approved',
          'approved_by': approver,
        }).eq('id', id);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Approved')));
      setState(() {}); // refresh list (the row will disappear)
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Approve failed: ${e.message}')));
    }
  }

  Future<void> _delete(String id) async {
    if (!_isAdmin) return;
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
        return await _sb.from('main_ledger').delete().eq('id', id);
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Deleted')));
      setState(() {}); // refresh list
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
        title: Text(
          'Main Pending Approvals',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: _green,
          onRefresh: _refresh,
          child: FutureBuilder<List<_PendingRow>>(
            future: _loadPending(),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snap.data ?? const <_PendingRow>[];
              if (rows.isEmpty) {
                return const Center(child: Text('No pending approvals'));
              }

              return ListView.separated(
                padding: EdgeInsets.all(rs.space(12)),
                itemCount: rows.length,
                separatorBuilder: (_, __) => SizedBox(height: rs.space(8)),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final isIncome = r.type == 'income';
                  final color = isIncome ? Colors.green : Colors.red;
                  final title = isIncome ? 'Income' : 'Expense';

                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(rs.radius(14)),
                      side: BorderSide(color: _green.withValues(alpha: 0.15)),
                    ),
                    child: Theme(
                      // Tweak ExpansionTile colors
                      data: Theme.of(context).copyWith(
                        dividerColor: Colors.transparent,
                        listTileTheme: ListTileTheme.of(
                          context,
                        ).copyWith(iconColor: _green),
                      ),
                      child: ExpansionTile(
                        leading: Container(
                          height: rs.icon(40),
                          width: rs.icon(40),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(rs.radius(10)),
                          ),
                          child: Icon(
                            isIncome ? Icons.trending_up : Icons.trending_down,
                            color: color,
                            size: rs.icon(22),
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
                          '${(r.payeePayer == null || r.payeePayer!.isEmpty) ? '' : ' • ${r.payeePayer}'}'
                          '${(r.remarks == null || r.remarks!.isEmpty) ? '' : ' • ${r.remarks}'}',
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
                            child: _DetailsBlock(
                              row: r,
                              isAdmin: _isAdmin,
                              loadSignedUrl: _signedUrl,
                              onApprove: () => _approve(r.id),
                              onDelete: () => _delete(r.id),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _DetailsBlock extends StatefulWidget {
  const _DetailsBlock({
    required this.row,
    required this.isAdmin,
    required this.loadSignedUrl,
    required this.onApprove,
    required this.onDelete,
  });

  final _PendingRow row;
  final bool isAdmin;
  final Future<String?> Function(String path) loadSignedUrl;
  final VoidCallback onApprove;
  final VoidCallback onDelete;

  @override
  State<_DetailsBlock> createState() => _DetailsBlockState();
}

class _DetailsBlockState extends State<_DetailsBlock> {
  String? _imageUrl;
  bool _loadingImage = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadImage();
  }

  Future<void> _maybeLoadImage() async {
    final path = widget.row.attachmentPath;
    if (path == null || path.isEmpty) return;
    setState(() => _loadingImage = true);
    final url = await widget.loadSignedUrl(path);
    if (!mounted) return;
    setState(() {
      _imageUrl = url;
      _loadingImage = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final r = widget.row;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (r.paymentMode != null && r.paymentMode!.isNotEmpty) ...[
          Text(
            'Payment mode: ${r.paymentMode}',
            style: const TextStyle(color: _green),
          ),
          SizedBox(height: rs.space(4)),
        ],
        if (r.createdBy != null && r.createdBy!.trim().isNotEmpty) ...[
          Text(
            'Created by: ${r.createdBy}',
            style: const TextStyle(color: _green),
          ),
          SizedBox(height: rs.space(4)),
        ],
        if (r.remarks != null && r.remarks!.trim().isNotEmpty) ...[
          Text(
            'Notes: ${r.remarks}',
            style: TextStyle(color: _green.withValues(alpha: 0.9)),
          ),
          SizedBox(height: rs.space(8)),
        ],
        if (_loadingImage)
          Padding(
            padding: EdgeInsets.only(bottom: rs.space(8)),
            child: SizedBox(
              height: rs.icon(16),
              width: rs.icon(16),
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        if (_imageUrl != null)
          GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  child: InteractiveViewer(
                    child: Image.network(_imageUrl!, fit: BoxFit.contain),
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(rs.radius(10)),
              child: Image.network(
                _imageUrl!,
                height: rs.h(160),
                fit: BoxFit.cover,
              ),
            ),
          ),
        SizedBox(height: rs.space(12)),
        Row(
          children: [
            if (widget.isAdmin)
              FilledButton(
                onPressed: widget.onApprove,
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: _gold,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(rs.radius(10)),
                  ),
                  textStyle: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: rs.font(14),
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.space(14),
                    vertical: rs.space(10),
                  ),
                ),
                child: const Text('Approve'),
              ),
            SizedBox(width: rs.space(8)),
            if (widget.isAdmin)
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                icon: Icon(Icons.delete_outline, size: rs.icon(18)),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _green,
                  side: BorderSide(color: _green.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(rs.radius(10)),
                  ),
                  textStyle: TextStyle(fontSize: rs.font(14)),
                  padding: EdgeInsets.symmetric(
                    horizontal: rs.space(12),
                    vertical: rs.space(10),
                  ),
                ),
              ),
            const Spacer(),
          ],
        ),
      ],
    );
  }
}

class _PendingRow {
  _PendingRow({
    required this.id,
    required this.date,
    required this.amount,
    required this.type, // 'income' | 'expense'
    this.payeePayer,
    this.remarks,
    this.createdBy,
    this.attachmentPath,
    this.paymentMode,
  });

  final String id;
  final String date; // yyyy-MM-dd
  final double amount;
  final String type;
  final String? payeePayer;
  final String? remarks;
  final String? createdBy;
  final String? attachmentPath;
  final String? paymentMode;
}
