// lib/features/reports/advanced_filter_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';

// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class AdvancedFilterPage extends StatefulWidget {
  const AdvancedFilterPage({super.key});

  @override
  State<AdvancedFilterPage> createState() => _AdvancedFilterPageState();
}

enum _Status { approved, pending, all }

enum _Source { petty, main }

// Add a dedicated payment mode filter for main_ledger
// ignore: constant_identifier_names
enum _PayMode { all, cash, card, upi, bank_transfer }

class _AdvancedFilterPageState extends State<AdvancedFilterPage> {
  final _sb = Supabase.instance.client;

  // Emville theme colors
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  // Admin?
  bool _isAdmin = false;

  // Controls
  final _qCtrl = TextEditingController();
  DateTime _from = DateTime.now().subtract(const Duration(days: 31));
  DateTime _to = DateTime.now();
  _Status _status = _Status.all;
  bool _searchPetty = true;
  bool _searchMain = true;

  // NEW: payment mode filter (applies only to main_ledger)
  _PayMode _payMode = _PayMode.all;

  bool _loading = false;
  List<_ResultRow> _rows = [];

  final _df = DateFormat('yyyy-MM-dd');
  final _dfUi = DateFormat('dd MMM yyyy');

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  @override
  void dispose() {
    _qCtrl.dispose();
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
        _isAdmin =
            (role == 'owner' || role == 'admin' || role == 'super_admin');
      });
    } catch (_) {
      setState(() => _isAdmin = false);
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

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'From date',
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'To date',
    );
    if (picked != null) setState(() => _to = picked);
  }

  Future<void> _runSearch() async {
    if (!_searchPetty && !_searchMain) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one ledger to search')),
      );
      return;
    }

    setState(() {
      _loading = true;
      _rows = [];
    });

    final start = _df.format(DateTime(_from.year, _from.month, _from.day));
    final end = _df.format(DateTime(_to.year, _to.month, _to.day));
    final term = _qCtrl.text.trim();
    final ilike = term.isEmpty ? null : '%${term.replaceAll('%', r'\%')}%';

    final futures = <Future<List<_ResultRow>>>[];
    if (_searchPetty) futures.add(_queryPetty(start, end, ilike));
    if (_searchMain) futures.add(_searchMainLedger(start, end, ilike));

    try {
      final results = await Future.wait(futures);
      final merged = results.expand((e) => e).toList()
        ..sort((a, b) => b.dateStr.compareTo(a.dateStr)); // latest first
      setState(() {
        _rows = merged;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Search failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<_ResultRow>> _queryPetty(
    String start,
    String end,
    String? ilike,
  ) async {
    var q = _sb.from('petty_cash_ledger').select(
          'id, date, amount, transaction_type, remarks, transaction_status, entered_by, approved_by, attachment_path, created_time',
        ) as PostgrestFilterBuilder;

    q = q.gte('date', start).lte('date', end);

    if (_status != _Status.all) {
      q = q.eq('transaction_status', _status.name);
    }

    if (ilike != null) {
      // case-insensitive match across relevant text columns
      q = q.or(
        'remarks.ilike.$ilike,entered_by.ilike.$ilike,approved_by.ilike.$ilike',
      );
    }

    final rows = await q
        .order('date', ascending: false)
        .order('created_time', ascending: false);

    return (rows as List).map<_ResultRow>((m) {
      return _ResultRow(
        source: _Source.petty,
        id: m['id'] as String,
        dateStr: (m['date'] as String?) ??
            ((m['created_time'] as String?) ?? '').split('T').first,
        amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
        type: (m['transaction_type'] as String?) ?? 'expense',
        status: (m['transaction_status'] as String?) ?? 'pending',
        titleLeft: (m['remarks'] as String?)?.trim().isNotEmpty == true
            ? m['remarks'] as String
            : 'Petty cash',
        createdBy: m['entered_by'] as String?,
        approvedBy: m['approved_by'] as String?,
        attachmentPath: m['attachment_path'] as String?,
      );
    }).toList();
  }

  Future<List<_ResultRow>> _searchMainLedger(
    String start,
    String end,
    String? ilike,
  ) async {
    var q = _sb.from('main_ledger').select(
          'id, date, amount, transaction_type, payee_payer_name, remarks, transaction_status, created_by, approved_by, attachment_path, created_time, payment_mode',
        ) as PostgrestFilterBuilder;

    q = q.gte('date', start).lte('date', end);

    if (_status != _Status.all) {
      q = q.eq('transaction_status', _status.name);
    }

    // Text search (no enums here)
    if (ilike != null) {
      q = q.or(
        'payee_payer_name.ilike.$ilike,remarks.ilike.$ilike,created_by.ilike.$ilike,approved_by.ilike.$ilike',
      );
    }

    // NEW: payment_mode equality filter (safe for enum)
    if (_payMode != _PayMode.all) {
      final modeStr = switch (_payMode) {
        _PayMode.cash => 'cash',
        _PayMode.card => 'card',
        _PayMode.upi => 'upi',
        _PayMode.bank_transfer => 'bank_transfer',
        _ => 'all',
      };
      if (modeStr != 'all') {
        q = q.eq('payment_mode', modeStr);
      }
    }

    final rows = await q
        .order('date', ascending: false)
        .order('created_time', ascending: false);

    return (rows as List).map<_ResultRow>((m) {
      final whom = (m['payee_payer_name'] as String?) ?? '';
      final notes = (m['remarks'] as String?) ?? '';
      final title = (whom.isNotEmpty && notes.isNotEmpty)
          ? '$whom — $notes'
          : (whom.isNotEmpty
              ? whom
              : (notes.isNotEmpty ? notes : 'Main ledger'));
      return _ResultRow(
        source: _Source.main,
        id: m['id'] as String,
        dateStr: (m['date'] as String?) ??
            ((m['created_time'] as String?) ?? '').split('T').first,
        amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
        type: (m['transaction_type'] as String?) ?? 'expense',
        status: (m['transaction_status'] as String?) ?? 'pending',
        titleLeft: title,
        createdBy: m['created_by'] as String?,
        approvedBy: m['approved_by'] as String?,
        attachmentPath: m['attachment_path'] as String?,
        paymentMode: m['payment_mode'] as String?,
      );
    }).toList();
  }

  Future<void> _approve(_ResultRow row) async {
    if (!_isAdmin) return;
    final approverName = await _currentUserFullName();
    final table =
        row.source == _Source.petty ? 'petty_cash_ledger' : 'main_ledger';
    try {
      await supabaseCall(() async {
        return await _sb.from(table).update({
          'transaction_status': 'approved',
          'approved_by': approverName,
        }).eq('id', row.id);
      });
      if (!mounted) return;
      setState(() {
        _rows = _rows.map((r) {
          if (r.id == row.id && r.source == row.source) {
            return r.copyWith(status: 'approved', approvedBy: approverName);
          }
          return r;
        }).toList();
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Approved')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approve failed: ${e.message}')));
    }
  }

  Future<void> _delete(_ResultRow row) async {
    if (!_isAdmin) return;
    final ok = await showDialog<bool>(
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final table =
        row.source == _Source.petty ? 'petty_cash_ledger' : 'main_ledger';
    try {
      await supabaseCall(() async {
        return await _sb.from(table).delete().eq('id', row.id);
      });
      if (!mounted) return;
      setState(() =>
          _rows.removeWhere((r) => r.id == row.id && r.source == row.source));
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Deleted')));
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: ${e.message}')));
    }
  }

  Future<String?> _signedUrl(String path) async {
    try {
      return await supabaseCall(() async {
        return await _sb.storage.from('receipts').createSignedUrl(path, 600);
      });
    } catch (_) {
      return null;
    }
  }

  void _showDetails(_ResultRow row) async {
    final rs = ResponsiveSize.of(context);

    String? imageUrl;
    if (row.attachmentPath != null && row.attachmentPath!.trim().isNotEmpty) {
      imageUrl = await _signedUrl(row.attachmentPath!);
    }
    if (!mounted) return;

    final isApproved = row.status == 'approved';
    final isIncome = row.type == 'income';
    final color = isIncome ? Colors.green : Colors.red;

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
              row.source == _Source.petty
                  ? (isIncome ? 'Petty: Income' : 'Petty: Expense')
                  : (isIncome ? 'Main: Income' : 'Main: Expense'),
              style: TextStyle(
                fontSize: rs.font(18),
                fontWeight: FontWeight.bold,
                color: _green,
              ),
            ),
            SizedBox(height: rs.space(6)),
            Text('Date: ${row.dateStr}', style: const TextStyle(color: _green)),
            SizedBox(height: rs.space(4)),
            Text(
              'Amount: ₹${row.amount.toStringAsFixed(2)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: rs.space(4)),
            Text('Status: ${row.status}',
                style: const TextStyle(color: _green)),
            if (row.paymentMode != null && row.paymentMode!.isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Payment mode: ${row.paymentMode}',
                  style: const TextStyle(color: _green)),
            ],
            if (row.createdBy != null && row.createdBy!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Created by: ${row.createdBy}',
                  style: const TextStyle(color: _green)),
            ],
            if (row.approvedBy != null &&
                row.approvedBy!.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Approved by: ${row.approvedBy}',
                  style: const TextStyle(color: _green)),
            ],
            if (row.titleLeft.trim().isNotEmpty) ...[
              SizedBox(height: rs.space(4)),
              Text('Details: ${row.titleLeft}',
                  style: const TextStyle(color: _green)),
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
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: _gold,
                      padding: EdgeInsets.symmetric(
                        horizontal: rs.space(16),
                        vertical: rs.space(10),
                      ),
                      textStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: rs.font(14),
                      ),
                    ),
                    onPressed: () => _approve(row),
                    child: const Text('Approve'),
                  ),
                  SizedBox(width: rs.space(8)),
                ],
                if (_isAdmin)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: const BorderSide(color: _green),
                      padding: EdgeInsets.symmetric(
                        horizontal: rs.space(12),
                        vertical: rs.space(10),
                      ),
                      textStyle: TextStyle(fontSize: rs.font(14)),
                    ),
                    onPressed: () => _delete(row),
                    icon: Icon(Icons.delete_outline, size: rs.icon(20)),
                    label: const Text('Delete'),
                  ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: _green,
                    textStyle: TextStyle(fontSize: rs.font(14)),
                  ),
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

  Widget _filterRow() {
    final rs = ResponsiveSize.of(context);

    final segStyle = ButtonStyle(
      side: WidgetStateProperty.all(
        const BorderSide(color: _green, width: 1.2),
      ),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((_) => _green),
      backgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => states.contains(WidgetState.selected)
            ? _gold.withValues(alpha: 0.18)
            : Colors.white,
      ),
      overlayColor: WidgetStateProperty.all(_green.withValues(alpha: 0.06)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(rs.radius(10))),
      ),
      textStyle: WidgetStateProperty.all(TextStyle(fontSize: rs.font(13))),
      padding: WidgetStateProperty.all(
        EdgeInsets.symmetric(horizontal: rs.space(10), vertical: rs.space(8)),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Search text
        TextField(
          controller: _qCtrl,
          decoration: InputDecoration(
            labelText: 'Search (remarks / names)',
            labelStyle: const TextStyle(color: _green),
            prefixIcon: Icon(Icons.search, color: _green, size: rs.icon(20)),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _green),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: _gold, width: 1.5),
            ),
          ),
          style: const TextStyle(color: _green),
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _runSearch(),
        ),
        SizedBox(height: rs.space(12)),

        // Ledger toggles + payment mode
        Wrap(
          spacing: rs.space(8),
          runSpacing: rs.space(8),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              label: Text(
                'Petty cash',
                style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w600,
                  fontSize: rs.font(13),
                ),
              ),
              selectedColor: _gold.withValues(alpha: 0.25),
              side: const BorderSide(color: _green),
              selected: _searchPetty,
              onSelected: (v) => setState(() => _searchPetty = v),
              backgroundColor: Colors.white,
              checkmarkColor: _green,
            ),
            FilterChip(
              label: Text(
                'Main ledger',
                style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w600,
                  fontSize: rs.font(13),
                ),
              ),
              selectedColor: _gold.withValues(alpha: 0.25),
              side: const BorderSide(color: _green),
              selected: _searchMain,
              onSelected: (v) => setState(() => _searchMain = v),
              backgroundColor: Colors.white,
              checkmarkColor: _green,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Payment mode: ',
                  style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w600,
                      fontSize: rs.font(13)),
                ),
                SizedBox(width: rs.space(8)),
                DropdownButton<_PayMode>(
                  value: _payMode,
                  dropdownColor: Colors.white,
                  style: TextStyle(color: _green, fontSize: rs.font(14)),
                  iconEnabledColor: _green,
                  onChanged: (v) => setState(() => _payMode = v!),
                  items: const [
                    DropdownMenuItem(value: _PayMode.all, child: Text('All')),
                    DropdownMenuItem(value: _PayMode.cash, child: Text('Cash')),
                    DropdownMenuItem(value: _PayMode.card, child: Text('Card')),
                    DropdownMenuItem(value: _PayMode.upi, child: Text('UPI')),
                    DropdownMenuItem(
                      value: _PayMode.bank_transfer,
                      child: Text('Bank Transfer'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: rs.space(12)),

        // Status
        SegmentedButton<_Status>(
          style: segStyle,
          segments: const [
            ButtonSegment(value: _Status.approved, label: Text('Approved')),
            ButtonSegment(value: _Status.pending, label: Text('Pending')),
            ButtonSegment(value: _Status.all, label: Text('All')),
          ],
          selected: {_status},
          onSelectionChanged: (s) => setState(() => _status = s.first),
        ),
        SizedBox(height: rs.space(12)),

        // Date range
        Row(
          children: [
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'From',
                  style: TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                    fontSize: rs.font(14),
                  ),
                ),
                subtitle: Text(
                  _dfUi.format(_from),
                  style: const TextStyle(color: _green),
                ),
                trailing: IconButton(
                  icon:
                      Icon(Icons.date_range, color: _green, size: rs.icon(22)),
                  onPressed: _pickFrom,
                ),
              ),
            ),
            SizedBox(width: rs.space(8)),
            Expanded(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'To',
                  style: TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                    fontSize: rs.font(14),
                  ),
                ),
                subtitle: const Text(
                  // _dfUi.format(_to) is dynamic; keep const wrapper false:
                  // replaced below with non-const
                  '',
                  // will be replaced in build block below
                ),
                // We can’t keep const subtitle because it depends on _to:
              ),
            ),
          ],
        ),
        // Fix dynamic subtitle for "To"
        Builder(builder: (ctx) {
          return Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: Icon(Icons.date_range, color: _green, size: rs.icon(22)),
              onPressed: _pickTo,
            ),
          );
        }),
        SizedBox(height: rs.space(8)),

        // Run
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _gold,
              padding: EdgeInsets.symmetric(
                horizontal: rs.space(16),
                vertical: rs.space(14),
              ),
              textStyle: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: rs.font(14),
              ),
            ),
            icon: Icon(Icons.filter_alt_outlined, size: rs.icon(20)),
            label: const Text('Apply Filters'),
            onPressed: _runSearch,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Advanced Filter',
          style: TextStyle(
              color: _gold, fontWeight: FontWeight.bold, fontSize: rs.font(18)),
        ),
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: _gold),
      ),
      body: SafeArea(
        minimum: EdgeInsets.all(rs.space(12)),
        child: Column(
          children: [
            _filterRow(),
            SizedBox(height: rs.space(8)),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? const Center(
                          child: Text(
                            'No results',
                            style: TextStyle(color: _green),
                          ),
                        )
                      : Scrollbar(
                          child: ListView.separated(
                            itemCount: _rows.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: rs.space(8)),
                            itemBuilder: (context, i) {
                              final r = _rows[i];
                              final isIncome = r.type == 'income';
                              final color =
                                  isIncome ? Colors.green : Colors.red;
                              final prefix =
                                  r.source == _Source.petty ? 'Petty' : 'Main';
                              final kind = isIncome ? 'Income' : 'Expense';
                              return Card(
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(rs.radius(12)),
                                ),
                                elevation: 2,
                                child: ListTile(
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: rs.space(6),
                                    horizontal: rs.space(12),
                                  ),
                                  onTap: () => _showDetails(r),
                                  leading: Container(
                                    height: rs.icon(40),
                                    width: rs.icon(40),
                                    decoration: BoxDecoration(
                                      color: _green,
                                      borderRadius:
                                          BorderRadius.circular(rs.radius(10)),
                                    ),
                                    child: Icon(
                                      isIncome
                                          ? Icons.trending_up
                                          : Icons.trending_down,
                                      color: _gold,
                                      size: rs.icon(22),
                                    ),
                                  ),
                                  title: Text(
                                    '$prefix • $kind • ₹${r.amount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.w700,
                                      fontSize: rs.font(14),
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${r.dateStr}'
                                    '${r.titleLeft.isEmpty ? '' : ' • ${r.titleLeft}'}'
                                    '${_isAdmin ? ' • ${r.status}' : ''}',
                                    style: TextStyle(
                                      color: _green.withValues(alpha: 0.8),
                                      fontSize: rs.font(12.5),
                                    ),
                                  ),
                                  trailing: Icon(Icons.chevron_right,
                                      color: _green, size: rs.icon(22)),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- Model ----------
class _ResultRow {
  _ResultRow({
    required this.source,
    required this.id,
    required this.dateStr, // yyyy-MM-dd
    required this.amount,
    required this.type, // 'income' | 'expense'
    required this.status, // 'pending' | 'approved'
    required this.titleLeft,
    this.createdBy,
    this.approvedBy,
    this.attachmentPath,
    this.paymentMode,
  });

  final _Source source;
  final String id;
  final String dateStr;
  final double amount;
  final String type;
  final String status;
  final String titleLeft;
  final String? createdBy;
  final String? approvedBy;
  final String? attachmentPath;
  final String? paymentMode;

  _ResultRow copyWith({String? status, String? approvedBy}) => _ResultRow(
        source: source,
        id: id,
        dateStr: dateStr,
        amount: amount,
        type: type,
        status: status ?? this.status,
        titleLeft: titleLeft,
        createdBy: createdBy,
        approvedBy: approvedBy ?? this.approvedBy,
        attachmentPath: attachmentPath,
        paymentMode: paymentMode,
      );
}
