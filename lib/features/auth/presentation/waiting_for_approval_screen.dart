// lib/features/auth/presentation/waiting_for_approval_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_gate.dart';

// ⬇️ use your responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class WaitingForApprovalScreen extends StatefulWidget {
  const WaitingForApprovalScreen({super.key});

  @override
  State<WaitingForApprovalScreen> createState() =>
      _WaitingForApprovalScreenState();
}

class _WaitingForApprovalScreenState extends State<WaitingForApprovalScreen> {
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final supabase = Supabase.instance.client;
  bool _checking = false;

  Future<void> _checkApproval() async {
    setState(() => _checking = true);

    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _checking = false);
      return;
    }

    try {
      final res = await supabase
          .from('users')
          .select('approved, role')
          .eq('uid', uid)
          .maybeSingle();

      if (!mounted) return;

      // Debug: see exactly what came back
      // ignore: avoid_print
      print('[WAITING] check uid=$uid -> $res');

      final role = res?['role'] as String?;
      final isAdmin = role == 'owner' || role == 'admin';
      final approved = (res?['approved'] == true);

      if (isAdmin || approved) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthGate()),
          (route) => false,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still waiting for admin approval.')),
        );
      }
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database error: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error checking approval: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        title: Text(
          'Waiting for Approval',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
        iconTheme: const IconThemeData(color: _gold),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(rs.space(24)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveSize.panelMaxWidth(context),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_clock, size: rs.icon(72), color: Colors.grey),
                SizedBox(height: rs.space(20)),
                Text(
                  'Your account is awaiting admin approval.\n'
                  'You’ll be able to use the app once approved.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: rs.font(14)),
                ),
                SizedBox(height: rs.space(30)),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _gold,
                    padding: EdgeInsets.symmetric(vertical: rs.space(12)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(rs.radius(12)),
                    ),
                    textStyle: TextStyle(
                      fontSize: rs.font(14),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: _checking ? null : _checkApproval,
                  icon: _checking
                      ? SizedBox(
                          width: rs.icon(18),
                          height: rs.icon(18),
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.refresh, size: rs.icon(20)),
                  label: const Text('Check Again'),
                ),
                SizedBox(height: rs.space(16)),
                TextButton(
                  onPressed: () async {
                    try {
                      await supabase.auth.signOut(scope: SignOutScope.global);
                    } finally {
                      // ignore: control_flow_in_finally
                      if (!mounted) return;
                      Navigator.of(
                        // ignore: use_build_context_synchronously
                        context,
                        rootNavigator: true,
                      ).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthGate()),
                        (route) => false,
                      );
                    }
                  },
                  child: Text(
                    'Log out',
                    style: TextStyle(fontSize: rs.font(14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
