// lib/features/auth/presentation/signup_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'waiting_for_approval_screen.dart';

// 👇 responsive barrel
import 'package:emville_pms/responsive/responsive.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _sending = false;
  bool _sent = false;

  bool _obscurePw = true;
  bool _obscureConfirm = true;

  // stash password until after OTP verify
  String? _pendingPassword;

  StreamSubscription<AuthState>? _authSub;

  void _goToWaitingAndClearStack() {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const WaitingForApprovalScreen(),
        settings: const RouteSettings(name: 'waiting'),
        fullscreenDialog: true,
      ),
      (route) => false,
    );
  }

  Future<void> _postSignInSetup() async {
    final u = _sb.auth.currentUser;
    if (u == null) return;

    final fullName = _nameCtrl.text.trim();
    final email = u.email ?? _emailCtrl.text.trim();

    // 1) Best-effort: attach full_name to user metadata
    try {
      if (fullName.isNotEmpty) {
        await _sb.auth.updateUser(
          UserAttributes(data: {'full_name': fullName}),
        );
      }
    } catch (_) {
      // non-blocking
    }

    // 2) Ensure a row exists in public.users (start restricted)
    try {
      await _sb.from('users').upsert({
        'uid': u.id,
        'email': email,
        'full_name': fullName.isEmpty ? (email.split('@').first) : fullName,
        'role': 'user',
        'approved': false,
        'is_authorized': false,
      }, onConflict: 'uid');
    } catch (_) {
      // non-blocking: RLS still protects access
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Signed in. Your account is awaiting admin approval.'),
      ),
    );

    _goToWaitingAndClearStack();
  }

  @override
  void initState() {
    super.initState();

    // If a session appears (rare race), do post-setup
    _authSub = _sb.auth.onAuthStateChange.listen((data) async {
      if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.initialSession) {
        await _postSignInSetup();
      }
    });

    // Safety net after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final hasSession = _sb.auth.currentSession != null;
      if (hasSession) _postSignInSetup();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // --- Validators -----------------------------------------------------------
  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'Full name is required';
    if (v.trim().length < 2) return 'Please enter your full name';
    return null;
  }

  String? _validateEmail(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Email is required';
    final ok = RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(t);
    if (!ok) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    final t = v ?? '';
    if (t.length < 8) return 'Min 8 characters';
    if (!RegExp(r'[a-z]').hasMatch(t)) return 'Include a lowercase letter';
    if (!RegExp(r'[A-Z]').hasMatch(t)) return 'Include an uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(t)) return 'Include a number';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  // Make the decoration responsive without changing its signature.
  InputDecoration _decoration(String label, IconData icon) {
    final rs = ResponsiveSize(context);
    final tokens = ResponsiveTokens.of(context);
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: rs.font(14)),
      prefixIcon: Icon(icon, color: _green, size: rs.icon(20)),
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

  // --- OTP flow -------------------------------------------------------------

  Future<void> _sendSignInCode() async {
    if (!_formKey.currentState!.validate()) return;

    _pendingPassword = _passwordCtrl.text;

    setState(() => _sending = true);
    try {
      final email = _emailCtrl.text.trim();

      // Sends a 6-digit code (no deep link)
      await _sb.auth.signInWithOtp(email: email, shouldCreateUser: true);

      if (!mounted) return;
      setState(() => _sent = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A 6-digit code was sent to $email.')),
      );

      await _promptForEmailCode(email);
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Something went wrong sending the code')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _promptForEmailCode(String email) async {
    final codeCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final rs = ResponsiveSize(dialogCtx);
        int secondsLeft = 25;
        bool verifying = false;
        String? errorText;
        Timer? ticker;

        void startCooldown([int s = 30]) {
          secondsLeft = s;
          ticker?.cancel();
          ticker = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted) return;
            if (secondsLeft > 0) {
              secondsLeft--;
              (dialogCtx as Element).markNeedsBuild();
            } else {
              ticker?.cancel();
            }
          });
        }

        Future<void> resend() async {
          if (secondsLeft > 0 || verifying) return;
          try {
            await _sb.auth.signInWithOtp(email: email, shouldCreateUser: true);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('New code sent to $email')),
              );
            }
            startCooldown(30);
          } on AuthException catch (e) {
            errorText = e.message.isNotEmpty ? e.message : 'Could not resend.';
            (dialogCtx as Element).markNeedsBuild();
          } catch (_) {
            errorText = 'Something went wrong resending code.';
            (dialogCtx as Element).markNeedsBuild();
          }
        }

        Future<void> verify() async {
          final code = codeCtrl.text.trim();
          if (code.length != 6) {
            errorText = 'Enter the 6-digit code';
            (dialogCtx as Element).markNeedsBuild();
            return;
          }

          verifying = true;
          errorText = null;
          (dialogCtx as Element).markNeedsBuild();

          try {
            // 1) Create session using the code
            await _sb.auth.verifyOTP(
              email: email,
              token: code,
              type: OtpType.email,
            );

            // 2) Set password if provided
            final pw = _pendingPassword;
            if (pw != null && pw.isNotEmpty) {
              try {
                await _sb.auth.updateUser(UserAttributes(password: pw));
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Signed in, but setting password failed. You can set it later in Profile.',
                      ),
                    ),
                  );
                }
              }
            }

            if (!mounted) return;
            ticker?.cancel();
            // ignore: use_build_context_synchronously
            Navigator.of(dialogCtx).pop(); // close dialog
            await _postSignInSetup();
          } on AuthException catch (e) {
            verifying = false;
            errorText = e.message.isNotEmpty ? e.message : 'Invalid code.';
            (dialogCtx).markNeedsBuild();
          } catch (_) {
            verifying = false;
            errorText = 'Something went wrong. Try again.';
            (dialogCtx).markNeedsBuild();
          }
        }

        // kick off initial cooldown
        startCooldown(25);

        return PopScope(
          canPop: true, // allow normal back navigation
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (!didPop) {
              ticker?.cancel();
            }
          },
          child: AlertDialog(
            title: ResponsiveText('Enter the 6-digit code',
                style: TextStyle(
                    fontSize: rs.font(18), fontWeight: FontWeight.w600)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    hintText: '123456',
                    counterText: '',
                  ),
                  onSubmitted: (_) {
                    if (!verifying) verify();
                  },
                  enabled: !verifying,
                ),
                if (errorText != null) ...[
                  SizedBox(height: rs.space(8)),
                  Text(
                    errorText!,
                    style: TextStyle(color: Colors.red, fontSize: rs.font(13)),
                  ),
                ],
                SizedBox(height: rs.space(8)),
                TextButton.icon(
                  onPressed: (secondsLeft > 0 || verifying) ? null : resend,
                  icon: const Icon(Icons.refresh),
                  label: Text(
                    secondsLeft > 0
                        ? 'Resend in ${secondsLeft}s'
                        : 'Resend code',
                    style: TextStyle(fontSize: rs.font(14)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: verifying
                    ? null
                    : () {
                        ticker?.cancel();
                        Navigator.of(dialogCtx).pop();
                      },
                child: Text('Cancel', style: TextStyle(fontSize: rs.font(14))),
              ),
              FilledButton.icon(
                onPressed: verifying ? null : verify,
                icon: verifying
                    ? SizedBox(
                        width: rs.w(18),
                        height: rs.w(18),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.verified),
                label: Text('Verify', style: TextStyle(fontSize: rs.font(14))),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rs = ResponsiveSize(context);
    final tokens = ResponsiveTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: IconThemeData(color: _gold, size: rs.icon(22)),
        title: ResponsiveText(
          'Sign up',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(rs.w(16)),
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radius),
              ),
              child: Padding(
                padding: EdgeInsets.all(tokens.padding),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Full name
                      TextFormField(
                        controller: _nameCtrl,
                        enabled: !_sent,
                        validator: _validateName,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(fontSize: rs.font(14)),
                        decoration: _decoration(
                          'Full Name',
                          Icons.person_outline,
                        ),
                      ),
                      SizedBox(height: rs.space(12)),

                      // Email
                      TextFormField(
                        controller: _emailCtrl,
                        enabled: !_sent,
                        validator: _validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(fontSize: rs.font(14)),
                        decoration: _decoration('Email', Icons.email_outlined),
                      ),
                      SizedBox(height: rs.space(12)),

                      // Password
                      TextFormField(
                        controller: _passwordCtrl,
                        enabled: !_sent,
                        obscureText: _obscurePw,
                        validator: _validatePassword,
                        textInputAction: TextInputAction.next,
                        style: TextStyle(fontSize: rs.font(14)),
                        decoration: _decoration('Password', Icons.lock_outline)
                            .copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePw
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: rs.icon(20),
                            ),
                            onPressed: () =>
                                setState(() => _obscurePw = !_obscurePw),
                          ),
                          helperText: 'Min 8 chars, 1 a–z, 1 A–Z, 1 number',
                          helperStyle: TextStyle(fontSize: rs.font(12)),
                        ),
                      ),
                      SizedBox(height: rs.space(12)),

                      // Confirm password
                      TextFormField(
                        controller: _confirmCtrl,
                        enabled: !_sent,
                        obscureText: _obscureConfirm,
                        validator: _validateConfirm,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: rs.font(14)),
                        decoration: _decoration(
                          'Confirm password',
                          Icons.lock_person_outlined,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                              size: rs.icon(20),
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirm = !_obscureConfirm,
                            ),
                          ),
                        ),
                        onFieldSubmitted: (_) {
                          if (!_sending && !_sent) _sendSignInCode();
                        },
                      ),

                      SizedBox(height: rs.space(16)),

                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: _green,
                                foregroundColor: _gold,
                                padding: EdgeInsets.symmetric(
                                  vertical: rs.h(14),
                                  horizontal: rs.w(12),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(tokens.radius),
                                ),
                              ),
                              onPressed:
                                  _sending || _sent ? null : _sendSignInCode,
                              icon: _sending
                                  ? SizedBox(
                                      width: rs.w(18),
                                      height: rs.w(18),
                                      child: const CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation(_gold),
                                      ),
                                    )
                                  : Icon(Icons.key, size: rs.icon(20)),
                              label: Text(
                                'Send sign-in code',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: rs.font(14),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_sent) ...[
                        SizedBox(height: rs.space(12)),
                        Container(
                          padding: EdgeInsets.all(rs.w(12)),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(tokens.radius),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.mark_email_read_outlined,
                                  color: _green, size: rs.icon(20)),
                              SizedBox(width: rs.w(12)),
                              Expanded(
                                child: Text(
                                  'We’ve sent a 6-digit code to your email.\n'
                                  'Enter it to finish sign-in. Your password will be set once you verify the code.\n\n'
                                  'Your account will remain restricted until an admin authorizes it.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: _green,
                                    fontSize: rs.font(13),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),

      // Debug helper to jump to Waiting if a session appears
      floatingActionButton: Builder(
        builder: (ctx) {
          final sess = _sb.auth.currentSession;
          final hasSession = sess != null && sess.user.id.isNotEmpty;
          return FloatingActionButton.extended(
            onPressed: hasSession
                ? () {
                    Navigator.of(ctx, rootNavigator: true).pushAndRemoveUntil(
                      MaterialPageRoute(
                        builder: (_) => const WaitingForApprovalScreen(),
                        settings: const RouteSettings(name: 'waiting'),
                      ),
                      (route) => false,
                    );
                  }
                : null,
            icon: const Icon(Icons.lock_open),
            label: Text(
              hasSession ? 'Go to Waiting' : 'No session yet',
              style: TextStyle(fontSize: rs.font(13)),
            ),
          );
        },
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(rs.w(8)),
          child: Text(
            'DEBUG session: ${_sb.auth.currentSession?.user.id ?? 'null'}',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: rs.font(12), color: Colors.grey),
          ),
        ),
      ),
    );
  }
}
