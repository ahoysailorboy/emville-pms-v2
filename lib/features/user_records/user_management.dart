// lib/features/user_records/user_management.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive helper (shared across app)
import 'package:emville_pms/responsive/responsive.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;
  bool _loading = false;
  String _myRole = 'user'; // owner/admin/user
  List<Map<String, dynamic>> _rows = const [];

  // Same fixed size for the two header buttons
  static const _btnSize = Size(120, 36);

  ButtonStyle get _btnGreen => FilledButton.styleFrom(
        backgroundColor: _green,
        foregroundColor: _gold,
        minimumSize: _btnSize,
        maximumSize: _btnSize,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle get _btnRed => FilledButton.styleFrom(
        backgroundColor: Colors.red,
        foregroundColor: Colors.white,
        minimumSize: _btnSize,
        maximumSize: _btnSize,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  // Disabled style (used for Owner's Approve button too)
  ButtonStyle get _btnDisabled => FilledButton.styleFrom(
        backgroundColor: Colors.grey.shade400,
        foregroundColor: Colors.white,
        minimumSize: _btnSize,
        maximumSize: _btnSize,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle get _btnDelete => FilledButton.styleFrom(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Who am I?
      final me = _sb.auth.currentUser;
      if (me != null) {
        final meRes = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('role')
              .eq('uid', me.id)
              .maybeSingle();
        });
        _myRole = (meRes?['role'] as String?) ?? 'user';
      }

      final res = await supabaseCall(() async {
        return await _sb
            .from('users_v')
            .select('uid, email, full_name, role, approved, is_authorized');
      });

      final list = (res as List).cast<Map<String, dynamic>>();

      // Sort: owner -> admin -> user; then A–Z by full_name
      const priority = {'owner': 0, 'admin': 1, 'user': 2};
      list.sort((a, b) {
        final ra = priority[(a['role'] as String?) ?? 'user'] ?? 3;
        final rb = priority[(b['role'] as String?) ?? 'user'] ?? 3;
        if (ra != rb) return ra.compareTo(rb);
        final na = (a['full_name'] as String? ?? '').toLowerCase();
        final nb = (b['full_name'] as String? ?? '').toLowerCase();
        return na.compareTo(nb);
      });

      setState(() => _rows = list);
    } catch (e) {
      _toast('Load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isAdmin => _myRole == 'owner' || _myRole == 'admin';

  // --- actions --------------------------------------------------------------

  Future<void> _toggleRole(Map<String, dynamic> row) async {
    if (!_isAdmin) return;

    final current = (row['role'] as String?) ?? 'user';
    if (current == 'owner') {
      _toast('Owner role cannot be changed.');
      return;
    }

    final uid = row['uid'] as String;
    final newRole = current == 'admin' ? 'user' : 'admin';

    try {
      // upsert into user_roles
      await supabaseCall(() async {
        return await _sb.from('user_roles').upsert({
          'user_id': uid,
          'role': newRole,
        }, onConflict: 'user_id');
      });
      await _load();
    } catch (e) {
      _toast('Updating role failed: $e');
    }
  }

  Future<void> _toggleApproved(Map<String, dynamic> row) async {
    if (!_isAdmin) return;
    final uid = row['uid'] as String;
    final role = (row['role'] as String?) ?? 'user';
    final isOwner = role == 'owner';
    if (isOwner) {
      _toast('Owner approval cannot be changed.');
      return;
    }

    final currentlyApproved = (row['approved'] as bool?) ?? false;
    try {
      // Toggle both flags together
      await supabaseCall(() async {
        return await _sb.from('users').update({
          'approved': !currentlyApproved,
          'is_authorized': !currentlyApproved,
        }).eq('uid', uid);
      });
      await _load();
    } catch (e) {
      _toast('Updating approval failed: $e');
    }
  }

  Future<void> _confirmAndDelete(Map<String, dynamic> row) async {
    if (!_isAdmin) return;
    final role = (row['role'] as String?) ?? 'user';
    if (role == 'owner') {
      _toast('Owner cannot be deleted.');
      return;
    }
    final uid = row['uid'] as String;
    final fullName = (row['full_name'] as String?) ?? 'this user';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm delete'),
        content: Text('This will soft-delete $fullName. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: _btnRed,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final res = await _sb.functions.invoke('delete-user', body: {'uid': uid});
      final data = res.data;
      if (data is Map && data['ok'] == true) {
        _toast('User deleted.');
        await _load();
      } else {
        final msg = (data is Map && data['error'] is String)
            ? data['error'] as String
            : 'Unknown error';
        _toast('Delete failed: $msg');
      }
      //} on SupabaseException catch (e) {
      // _toast('Delete failed: ${e.message}');
    } catch (e) {
      _toast('Delete failed: $e');
    }
  }

  // --- ui helpers -----------------------------------------------------------

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _roleButton(Map<String, dynamic> row) {
    final role = (row['role'] as String?) ?? 'user';
    final isOwner = role == 'owner';
    final label = isOwner ? 'Owner' : (role == 'admin' ? 'Admin' : 'User');

    return SizedBox(
      width: _btnSize.width,
      height: _btnSize.height,
      child: FilledButton(
        style: isOwner ? _btnDisabled : _btnGreen,
        onPressed: isOwner ? null : () => _toggleRole(row),
        child: Text(label),
      ),
    );
  }

  Widget _approveButton(Map<String, dynamic> row) {
    final role = (row['role'] as String?) ?? 'user';
    final isOwner = role == 'owner';
    final approved = (row['approved'] as bool?) ?? false;

    final style = isOwner ? _btnDisabled : (approved ? _btnGreen : _btnRed);
    final label = isOwner ? 'Approved' : (approved ? 'Approved' : 'Pending');

    return SizedBox(
      width: _btnSize.width,
      height: _btnSize.height,
      child: FilledButton(
        style: style,
        onPressed: isOwner ? null : () => _toggleApproved(row),
        child: Text(label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      // AppBar with white background, green title, green refresh
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'User Management',
          style: TextStyle(
            color: _green,
            fontWeight: FontWeight.w800,
            fontSize: rs.font(20),
          ),
        ),
        iconTheme: const IconThemeData(color: _green),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: _green),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? const Center(child: Text('No users found'))
              : SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1000),
                      child: ListView.separated(
                        padding: EdgeInsets.all(rs.space(12)),
                        separatorBuilder: (_, __) =>
                            SizedBox(height: rs.space(8)),
                        itemCount: _rows.length,
                        itemBuilder: (_, i) {
                          final row = _rows[i];
                          final name = (row['full_name'] as String?)?.trim();
                          final displayName = (name == null || name.isEmpty)
                              ? (row['email'] as String? ?? 'Unnamed')
                              : name;
                          final email = (row['email'] as String?) ?? '';

                          // Buttons widget (left-aligned)
                          final buttons = Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              alignment: WrapAlignment.start,
                              spacing: rs.space(10),
                              runSpacing: rs.space(8),
                              children: [_roleButton(row), _approveButton(row)],
                            ),
                          );

                          return _UserTile(
                            title: displayName,
                            email: email,
                            collapsedButtons: buttons, // under name (collapsed)
                            expandedButtons: buttons, // in body (expanded)
                            onDelete: () => _confirmAndDelete(row),
                            canDelete: ((row['role'] as String?) ?? 'user') !=
                                    'owner' &&
                                _isAdmin,
                            btnDeleteStyle: _btnDelete,
                          );
                        },
                      ),
                    ),
                  ),
                ),
    );
  }
}

// Expansion tile that:
// - Collapsed: shows [collapsedButtons] (left-aligned) below name.
// - Expanded: shows email under the title, then [expandedButtons] (left-aligned),
//   then a larger Delete button bottom-left a couple of lines below.
class _UserTile extends StatefulWidget {
  const _UserTile({
    required this.title,
    required this.email,
    required this.collapsedButtons,
    required this.expandedButtons,
    required this.onDelete,
    required this.canDelete,
    required this.btnDeleteStyle,
  });

  final String title;
  final String email;
  final Widget collapsedButtons;
  final Widget expandedButtons;
  final VoidCallback onDelete;
  final bool canDelete;
  final ButtonStyle btnDeleteStyle;

  @override
  State<_UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<_UserTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Card(
      elevation: _expanded ? 2 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: EdgeInsets.symmetric(
            horizontal: rs.space(16),
            vertical: rs.space(10),
          ),
          childrenPadding:
              EdgeInsets.fromLTRB(rs.space(16), 0, rs.space(16), rs.space(14)),
          title: Text(
            widget.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: rs.font(16),
            ),
          ),
          // Collapsed => left-aligned buttons under name.
          // Expanded   => subtitle becomes the email under the title.
          subtitle: Padding(
            padding: EdgeInsets.only(top: rs.space(6)),
            child: _expanded
                ? Text(
                    widget.email,
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: rs.font(13),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: widget.collapsedButtons,
                  ),
          ),
          children: _expanded
              ? [
                  SizedBox(height: rs.space(10)),
                  // Left-aligned buttons in expanded body
                  Align(
                    alignment: Alignment.centerLeft,
                    child: widget.expandedButtons,
                  ),
                  SizedBox(height: rs.space(16)),
                  // Delete bottom-right
                  Align(
                    alignment: Alignment.bottomRight,
                    child: FilledButton.icon(
                      style: widget.btnDeleteStyle,
                      onPressed: widget.canDelete ? widget.onDelete : null,
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Delete'),
                    ),
                  ),
                ]
              : const <Widget>[],
        ),
      ),
    );
  }
}
