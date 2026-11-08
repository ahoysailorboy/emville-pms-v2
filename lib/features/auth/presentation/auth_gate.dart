// lib/features/auth/presentation/auth_gate.dart
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/services/user_bootstrap.dart';
import 'package:emville_pms/features/home/presentation/home_shell.dart';
import 'package:emville_pms/features/auth/presentation/signup_page.dart';
import 'waiting_for_approval_screen.dart';
import 'package:emville_pms/services/oauth_bridge.dart';

// 👇 responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;

  bool _ranBootstrapForThisSession = false;
  String? _role; // populated by ensureUserBootstrap()

  Future<void> _maybeBootstrap() async {
    if (_ranBootstrapForThisSession) return;
    final session = supabase.auth.currentSession;
    if (session == null) return;

    _ranBootstrapForThisSession = true;
    try {
      // If you created the RPC, this ensures a users row exists. Ignore if missing.
      try {
        await supabase.rpc('ensure_user_row');
      } catch (_) {}

      final role = await ensureUserBootstrap();
      log('[AuthGate] ensureUserBootstrap -> $role');
      if (mounted) setState(() => _role = role);
    } catch (e) {
      log('[AuthGate] bootstrap error: $e');
    }
  }

  /// Returns { approved: bool, role: String? } for this uid.
  /// Returns { approved: bool?, role: String?, err: String? }
  Future<Map<String, dynamic>> _fetchGateStatus(String uid) async {
    final res = await supabase
        .from('users_v')
        .select('approved, role')
        .eq('uid', uid)
        .maybeSingle();

    if (res == null) {
      return {'approved': false, 'role': null};
    }
    return {
      'approved': (res['approved'] == true),
      'role': res['role'] as String?,
    };
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: supabase.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = supabase.auth.currentSession;
        final event = snapshot.data?.event;

        if (event == AuthChangeEvent.signedIn ||
            event == AuthChangeEvent.initialSession) {
          _maybeBootstrap();
        }

        // Signed-in path → decide by role/approved
        if (session != null) {
          _maybeBootstrap();

          final uid = session.user.id;
          return FutureBuilder<Map<String, dynamic>>(
            future: _fetchGateStatus(uid),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              // Prefer role from DB; fall back to what bootstrap discovered
              final roleFromDb = snap.data?['role'] as String?;
              final effectiveRole = roleFromDb ?? _role;

              // 🔒 Admin/Owner always bypass Waiting
              final isAdmin =
                  effectiveRole == 'owner' || effectiveRole == 'admin';
              if (isAdmin) {
                return HomeShell(role: effectiveRole);
              }

              // If the DB call failed, show a one-time toast then keep them at Waiting
              if (snap.hasError || (snap.data?['err'] as String?) != null) {
                final err = snap.error?.toString() ??
                    (snap.data?['err'] as String?) ??
                    'unknown';
                // ignore: avoid_print
                print('[AUTH_GATE] gate status error: $err');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  final m = ScaffoldMessenger.maybeOf(context);
                  if (m != null) {
                    m.clearSnackBars();
                    m.showSnackBar(
                      SnackBar(content: Text('User check failed: $err')),
                    );
                  }
                });
                return const WaitingForApprovalScreen();
              }

              final approved = (snap.data?['approved'] == true);
              if (approved) {
                return HomeShell(role: effectiveRole);
              }

              return const WaitingForApprovalScreen();
            },
          );
        }

        // Not signed in yet
        if (snapshot.connectionState == ConnectionState.waiting &&
            session == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (session == null) {
          _ranBootstrapForThisSession = false;
          _role = null;
          return const _SignInPage();
        }

        // Fallback
        return HomeShell(role: _role);
      },
    );
  }
}

/// Minimal sign-in screen styled with Emville colors + "Create account" button
/// and Social logins (Google + Apple).
class _SignInPage extends StatefulWidget {
  const _SignInPage();

  @override
  State<_SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<_SignInPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final supabase = Supabase.instance.client;
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  bool busy = false;
  bool socialBusy = false;

  @override
  void dispose() {
    emailCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _signin() async {
    setState(() => busy = true);
    try {
      await supabase.auth.signInWithPassword(
        email: emailCtrl.text.trim(),
        password: passCtrl.text,
      );
      // AuthGate will run ensureUserBootstrap() on signedIn/active session.
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sign-in failed')));
      log('[SignIn] unexpected error: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _goToSignup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SignupPage(),
        fullscreenDialog: true,
        settings: const RouteSettings(name: 'signup'),
      ),
    );
  }

  Future<void> _signinWithGoogle() async {
    setState(() => socialBusy = true);
    try {
      await oauthGoogle(); // 👈 use the bridge
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message.isEmpty
              ? 'Could not start Google sign-in.'
              : e.message),
        ),
      );
    } catch (_) {
      // Silent: some platforms throw here but still complete via deep link.
    } finally {
      if (mounted) setState(() => socialBusy = false);
    }
  }

  Future<void> _signinWithApple() async {
    setState(() => socialBusy = true);
    try {
      await oauthApple(); // 👈 use the bridge
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              e.message.isEmpty ? 'Could not start Apple sign-in.' : e.message),
        ),
      );
    } catch (_) {
      // Silent fallback as above.
    } finally {
      if (mounted) setState(() => socialBusy = false);
    }
  }

  InputDecoration _fieldDeco(String label, {IconData? icon}) {
    final rs = ResponsiveSize(context);
    final tokens = ResponsiveTokens.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: rs.font(14)),
      prefixIcon:
          icon != null ? Icon(icon, color: _green, size: rs.icon(20)) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _green, width: 1.8),
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: rs.w(14),
        vertical: rs.h(12),
      ),
    );
  }

  Widget _orDivider() {
    final rs = ResponsiveSize(context);
    return Row(
      children: [
        Expanded(child: Divider(color: _green.withValues(alpha: 0.2))),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: rs.w(8)),
          child: Text(
            'OR',
            style: TextStyle(
              color: _green.withValues(alpha: 0.7),
              fontSize: rs.font(12),
            ),
          ),
        ),
        Expanded(child: Divider(color: _green.withValues(alpha: 0.2))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    final rs = ResponsiveSize(context);
    final tokens = ResponsiveTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: ResponsiveText(
          'Emville PMS',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: _gold,
            fontSize: rs.font(18),
          ),
        ),
        backgroundColor: _green,
        iconTheme: IconThemeData(color: _gold, size: rs.icon(22)),
      ),
      body: SafeArea(
        minimum: EdgeInsets.all(rs.w(24)),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveSize.panelMaxWidth(context),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                ResponsiveText(
                  'Sign in',
                  style: TextStyle(
                    fontSize: rs.font(28),
                    fontWeight: FontWeight.w900,
                    color: _green,
                  ),
                ),
                SizedBox(height: rs.space(16)),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: _fieldDeco('Email', icon: Icons.email_outlined),
                ),
                SizedBox(height: rs.space(10)),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: _fieldDeco('Password', icon: Icons.lock_outline),
                ),
                SizedBox(height: rs.space(16)),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: _gold,
                    padding: EdgeInsets.symmetric(vertical: rs.h(14)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radius),
                    ),
                    textStyle: TextStyle(
                      fontSize: rs.font(14),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: busy ? null : _signin,
                  icon: busy
                      ? SizedBox(
                          height: rs.icon(18),
                          width: rs.icon(18),
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(_gold),
                          ),
                        )
                      : Icon(Icons.login, size: rs.icon(20)),
                  label: const Text('Continue'),
                ),
                SizedBox(height: rs.space(16)),
                _orDivider(),
                SizedBox(height: rs.space(16)),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    padding: EdgeInsets.symmetric(vertical: rs.h(12)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radius),
                    ),
                    textStyle: TextStyle(fontSize: rs.font(14)),
                  ),
                  onPressed: socialBusy ? null : _signinWithGoogle,
                  icon: socialBusy
                      ? SizedBox(
                          height: rs.icon(18),
                          width: rs.icon(18),
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.g_mobiledata, size: rs.icon(22)),
                  label: const Text('Continue with Google'),
                ),
                SizedBox(height: rs.space(8)),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    padding: EdgeInsets.symmetric(vertical: rs.h(12)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radius),
                    ),
                    textStyle: TextStyle(fontSize: rs.font(14)),
                  ),
                  onPressed: socialBusy ? null : _signinWithApple,
                  icon: socialBusy
                      ? SizedBox(
                          height: rs.icon(18),
                          width: rs.icon(18),
                          child:
                              const CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(isIOS ? Icons.apple : Icons.apple_outlined,
                          size: rs.icon(20)),
                  label: const Text('Continue with Apple'),
                ),
                SizedBox(height: rs.space(12)),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    padding: EdgeInsets.symmetric(vertical: rs.h(12)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(tokens.radius),
                    ),
                    textStyle: TextStyle(fontSize: rs.font(14)),
                  ),
                  onPressed: _goToSignup,
                  icon: Icon(Icons.person_add_alt_1, size: rs.icon(20)),
                  label: const Text('Create account'),
                ),
                const Spacer(),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Text(
                    '© Emville',
                    style: TextStyle(
                      color: Colors.black54,
                      fontSize: rs.font(12),
                    ),
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
