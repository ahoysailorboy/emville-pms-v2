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
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/startup_screen.dart';

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
                return const StartupScreen();
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
          return const StartupScreen();
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

  bool _hidePassword = true;
  void _passwordHelp() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('Forgot password?'),
              content: const Text(
                  'Please contact your property administrator to help restore access to your account.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got it'))
              ]));
  Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(top: 21, bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 11,
              fontWeight: FontWeight.w600)));
  @override
  Widget build(BuildContext context) {
    final locked = busy || socialBusy;
    return Scaffold(
        body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Stack(children: [
                      SizedBox(
                          height: 292,
                          child: Stack(fit: StackFit.expand, children: [
                            Image.asset(Emville.bedroom, fit: BoxFit.cover),
                            const DecoratedBox(
                                decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                  Colors.transparent,
                                  Color(0x70123D32)
                                ]))),
                            Positioned(
                                top: MediaQuery.paddingOf(context).top + 6,
                                left: 20,
                                child: Container(
                                    width: 138,
                                    color: Emville.ivory.withValues(alpha: .93),
                                    padding: const EdgeInsets.all(6),
                                    child: Image.asset(Emville.logo)))
                          ])),
                      Padding(
                          padding: const EdgeInsets.only(top: 267),
                          child: Container(
                              padding:
                                  const EdgeInsets.fromLTRB(27, 30, 27, 22),
                              decoration: const BoxDecoration(
                                  color: Emville.ivory,
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(28))),
                              child: AutofillGroup(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    const Text('YOUR PROPERTY, CONNECTED',
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 10,
                                            letterSpacing: 2)),
                                    const SizedBox(height: 9),
                                    Text('Welcome back.',
                                        style: Emville.heading(31)),
                                    const SizedBox(height: 9),
                                    const Text(
                                        'Sign in to take care of the day ahead.',
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 12,
                                            color: Emville.muted,
                                            height: 1.6)),
                                    _label('Email address'),
                                    SizedBox(
                                        height: 46,
                                        child: TextField(
                                            controller: emailCtrl,
                                            enabled: !locked,
                                            keyboardType:
                                                TextInputType.emailAddress,
                                            textInputAction:
                                                TextInputAction.next,
                                            autofillHints: const [
                                              AutofillHints.username
                                            ],
                                            style: const TextStyle(
                                                fontFamily: 'Roboto',
                                                fontSize: 13),
                                            decoration: const InputDecoration(
                                                hintText: 'you@example.com',
                                                contentPadding:
                                                    EdgeInsets.symmetric(
                                                        horizontal: 15,
                                                        vertical: 13)))),
                                    _label('Password'),
                                    SizedBox(
                                        height: 46,
                                        child: TextField(
                                            controller: passCtrl,
                                            enabled: !locked,
                                            obscureText: _hidePassword,
                                            autofillHints: const [
                                              AutofillHints.password
                                            ],
                                            style: const TextStyle(
                                                fontFamily: 'Roboto',
                                                fontSize: 13),
                                            onSubmitted: (_) {
                                              if (!locked) _signin();
                                            },
                                            decoration: InputDecoration(
                                                hintText: 'Enter your password',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 15,
                                                        vertical: 13),
                                                suffixIcon: IconButton(
                                                    tooltip: _hidePassword
                                                        ? 'Show password'
                                                        : 'Hide password',
                                                    icon: Icon(
                                                        _hidePassword
                                                            ? Icons
                                                                .visibility_outlined
                                                            : Icons
                                                                .visibility_off_outlined,
                                                        size: 17,
                                                        color: Emville.muted),
                                                    onPressed: () => setState(
                                                        () => _hidePassword =
                                                            !_hidePassword))))),
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                            style: TextButton.styleFrom(
                                                minimumSize: const Size(44, 34),
                                                padding: EdgeInsets.zero,
                                                textStyle: const TextStyle(
                                                    fontFamily: 'Roboto',
                                                    fontSize: 11)),
                                            onPressed: _passwordHelp,
                                            child: const Text(
                                                'Forgot password?'))),
                                    const SizedBox(height: 8),
                                    FilledButton(
                                        onPressed: locked ? null : _signin,
                                        child: busy
                                            ? const SizedBox(
                                                height: 18,
                                                width: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color: Emville.paper))
                                            : const Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                    Text('Sign in'),
                                                    SizedBox(width: 8),
                                                    Icon(Icons.arrow_forward,
                                                        size: 16)
                                                  ])),
                                    const SizedBox(height: 22),
                                    const Row(children: [
                                      Expanded(child: Divider()),
                                      Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: 14),
                                          child: Text('or continue with',
                                              style: TextStyle(
                                                  fontFamily: 'Roboto',
                                                  fontSize: 10,
                                                  color: Emville.muted))),
                                      Expanded(child: Divider())
                                    ]),
                                    const SizedBox(height: 22),
                                    Row(children: [
                                      Expanded(
                                          child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(44, 43)),
                                              onPressed: locked
                                                  ? null
                                                  : _signinWithGoogle,
                                              icon: const Icon(
                                                  Icons.g_mobiledata,
                                                  size: 20),
                                              label: const Text('Google',
                                                  style: TextStyle(
                                                      fontFamily: 'Roboto',
                                                      fontSize: 12)))),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                  minimumSize:
                                                      const Size(44, 43)),
                                              onPressed: locked
                                                  ? null
                                                  : _signinWithApple,
                                              icon: const Icon(Icons.apple,
                                                  size: 17),
                                              label: const Text('Apple',
                                                  style: TextStyle(
                                                      fontFamily: 'Roboto',
                                                      fontSize: 12))))
                                    ]),
                                    if (socialBusy)
                                      const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: Center(
                                              child: SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2)))),
                                    const SizedBox(height: 14),
                                    Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text('New to Emville? ',
                                              style: TextStyle(
                                                  fontFamily: 'Roboto',
                                                  fontSize: 11,
                                                  color: Emville.muted)),
                                          TextButton(
                                              style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  textStyle: const TextStyle(
                                                      fontFamily: 'Roboto',
                                                      fontSize: 11)),
                                              onPressed:
                                                  locked ? null : _goToSignup,
                                              child: const Text(
                                                  'Create an account'))
                                        ]),
                                  ])))),
                    ])))));
  }
}
