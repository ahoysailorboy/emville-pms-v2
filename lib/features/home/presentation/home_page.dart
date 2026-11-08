// lib/features/home/presentation/home_page.dart
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.role});

  /// Optional role passed from AuthGate after bootstrapping.
  final String? role;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _sb = Supabase.instance.client;

  Future<Map<String, String?>> _load() async {
    final user = _sb.auth.currentUser;
    if (user == null) {
      return {'email': null, 'uid': null, 'role': null, 'dbg': 'no session'};
    }

    // If AuthGate already gave us a role, use it and skip the query.
    if (widget.role != null) {
      return {
        'email': user.email,
        'uid': user.id,
        'role': widget.role,
        'dbg': 'role from AuthGate',
      };
    }

    try {
      final res = await supabaseCall(() async {
        return await _sb
            .from('user_roles')
            .select('role')
            .eq('user_id', user.id)
            .maybeSingle();
      });

      log('[home] user_id=${user.id}');
      log('[home] roles select result = $res');

      final role = res == null ? null : (res['role'] as String?);
      return {
        'email': user.email,
        'uid': user.id,
        'role': role,
        'dbg': res == null ? 'no row returned' : 'row returned',
      };
    } on PostgrestException catch (e) {
      log('[home] PostgrestException: ${e.message} (code=${e.code})');
      return {
        'email': user.email,
        'uid': user.id,
        'role': null,
        'dbg': 'PostgrestException: ${e.message} (${e.code})',
      };
    } catch (e) {
      log('[home] unexpected error: $e');
      return {
        'email': user.email,
        'uid': user.id,
        'role': null,
        'dbg': 'unexpected: $e',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return FutureBuilder<Map<String, String?>>(
      future: _load(),
      builder: (context, snap) {
        final supabase = Supabase.instance.client;

        if (snap.connectionState != ConnectionState.done) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                'Emville PMS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: rs.font(18),
                ),
              ),
            ),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final data = snap.data ?? const {};
        final email = data['email'] ?? '—';
        final uid = data['uid'] ?? '—';
        final role = data['role'] ?? 'no role';
        final dbg = data['dbg'] ?? '';

        return Scaffold(
          appBar: AppBar(
            title: Text(
              'Emville PMS',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: rs.font(18),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => supabase.auth.signOut(),
                tooltip: 'Sign out',
              ),
            ],
          ),
          body: Padding(
            padding: EdgeInsets.all(rs.space(24)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Signed in ✅',
                  style: TextStyle(
                    fontSize: rs.font(20),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: rs.space(12)),
                Text('Email: $email', style: TextStyle(fontSize: rs.font(14))),
                SizedBox(height: rs.space(4)),
                Text('UID: $uid', style: TextStyle(fontSize: rs.font(14))),
                SizedBox(height: rs.space(4)),
                Text('Role: $role', style: TextStyle(fontSize: rs.font(14))),
                if (dbg.isNotEmpty) ...[
                  SizedBox(height: rs.space(8)),
                  Text(
                    'DBG: $dbg',
                    style: TextStyle(color: Colors.grey, fontSize: rs.font(12)),
                  ),
                ],
                SizedBox(height: rs.space(24)),
                const Divider(),
                SizedBox(height: rs.space(12)),
                Text(
                  'Next: role-aware navigation (Owner/Admin/Caretaker).',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: rs.font(13),
                  ),
                ),
                SizedBox(height: rs.space(12)),
                FilledButton(
                  onPressed: () => setState(() {}),
                  child:
                      Text('Refresh', style: TextStyle(fontSize: rs.font(14))),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
