// lib/features/profile/my_profile.dart
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive helper
import 'package:emville_pms/responsive/responsive.dart';

class MyProfilePage extends StatefulWidget {
  const MyProfilePage({super.key});

  @override
  State<MyProfilePage> createState() => _MyProfilePageState();
}

class _MyProfilePageState extends State<MyProfilePage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController(); // read-only in UI

  final _curPwCtrl = TextEditingController();
  final _newPwCtrl = TextEditingController();
  final _confPwCtrl = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  final _pwKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _saving = false;
  bool _pwBusy = false;

  bool _obCur = true, _obNew = true, _obConf = true;

  // derived
  String? _uid;
  bool _isEmailPassword = false; // show change-password section if true

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _curPwCtrl.dispose();
    _newPwCtrl.dispose();
    _confPwCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final user = _sb.auth.currentUser;
      if (user == null) {
        _toast('Not signed in.');
        return;
      }
      _uid = user.id;

      // Provider check
      // Either appMetadata.provider == 'email' OR identities contain 'email'
      final meta = user.appMetadata;
      final providers =
          (meta['providers'] as List?)?.cast<String>() ?? const [];
      final provider = (meta['provider'] as String?) ??
          (providers.isNotEmpty ? providers.first : null);
      _isEmailPassword = (provider == 'email') || providers.contains('email');

      // Email
      _emailCtrl.text = user.email ?? '';

      // Try to fetch full_name from public.users; fallback to user_metadata if missing
      String fullName = '';
      try {
        final row = await supabaseCall(() async {
          return await _sb
              .from('users')
              .select('full_name')
              .eq('uid', user.id)
              .maybeSingle();
        });
        fullName = (row?['full_name'] as String?)?.trim() ?? '';
      } catch (_) {
        // ignore; fallback below
      }
      if (fullName.isEmpty) {
        final metaName = (user.userMetadata?['full_name'] as String?)?.trim();
        if (metaName != null && metaName.isNotEmpty) fullName = metaName;
      }
      if (fullName.isEmpty && _emailCtrl.text.isNotEmpty) {
        fullName = _emailCtrl.text.split('@').first;
      }
      _nameCtrl.text = fullName;
    } catch (e) {
      _toast('Failed to load profile: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_uid == null) return;

    setState(() => _saving = true);
    final newName = _nameCtrl.text.trim();
    try {
      // 1) Update public.users (RLS must allow user to update own row)
      await supabaseCall(() async {
        return await _sb
            .from('users')
            .update({'full_name': newName}).eq('uid', _uid!);
      });

      // 2) Best-effort: also mirror into auth user metadata
      try {
        await supabaseCall(() async {
          return await _sb.auth.updateUser(
            UserAttributes(data: {'full_name': newName}),
          );
        });
      } catch (e) {
        log('[MyProfile] update auth metadata failed: $e');
      }

      _toast('Profile saved.');
    } on PostgrestException catch (e) {
      _toast('Save failed: ${e.message}');
    } catch (e) {
      _toast('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Simple password rules (same as signup)
  String? _validatePassword(String? v) {
    final t = v ?? '';
    if (t.length < 8) return 'Min 8 characters';
    if (!RegExp(r'[a-z]').hasMatch(t)) return 'Include a lowercase letter';
    if (!RegExp(r'[A-Z]').hasMatch(t)) return 'Include an uppercase letter';
    if (!RegExp(r'[0-9]').hasMatch(t)) return 'Include a number';
    return null;
  }

  Future<void> _changePassword() async {
    if (!_isEmailPassword) return; // hidden anyway
    if (!_pwKey.currentState!.validate()) return;

    final newPw = _newPwCtrl.text;
    final confPw = _confPwCtrl.text;
    if (newPw != confPw) {
      _toast('New passwords do not match.');
      return;
    }

    setState(() => _pwBusy = true);
    try {
      // Supabase GoTrue lets an authenticated user set a new password
      await supabaseCall(() async {
        return await _sb.auth.updateUser(
          UserAttributes(password: newPw),
        );
      });

      // Optional: sign out locally to force re-login with new password
      // await _sb.auth.signOut();

      _curPwCtrl.clear();
      _newPwCtrl.clear();
      _confPwCtrl.clear();
      _toast('Password updated.');
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('Password update failed: $e');
    } finally {
      if (mounted) setState(() => _pwBusy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  InputDecoration _deco(String label, {IconData? icon}) => InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: _green) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: _green, width: 1.8),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        title: Text(
          'My Profile',
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
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout, color: _green),
            onPressed: () => _sb.auth.signOut(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: EdgeInsets.all(rs.space(16)),
                    children: [
                      // Profile card
                      Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(rs.space(16)),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                TextFormField(
                                  controller: _nameCtrl,
                                  decoration:
                                      _deco('Full Name', icon: Icons.person),
                                  style: TextStyle(fontSize: rs.font(14)),
                                  textInputAction: TextInputAction.done,
                                  validator: (v) {
                                    final t = v?.trim() ?? '';
                                    if (t.isEmpty) {
                                      return 'Full name is required';
                                    }
                                    if (t.length < 2) {
                                      return 'Please enter your full name';
                                    }
                                    return null;
                                  },
                                ),
                                SizedBox(height: rs.space(12)),
                                TextField(
                                  controller: _emailCtrl,
                                  readOnly: true,
                                  decoration: _deco(
                                    'Email',
                                    icon: Icons.email_outlined,
                                  ).copyWith(
                                    helperText: 'Email cannot be changed',
                                  ),
                                  style: TextStyle(fontSize: rs.font(14)),
                                ),
                                SizedBox(height: rs.space(16)),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _green,
                                      foregroundColor: _gold,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _saving ? null : _saveProfile,
                                    icon: _saving
                                        ? SizedBox(
                                            width: rs.space(18),
                                            height: rs.space(18),
                                            child:
                                                const CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.save),
                                    label: const Text('Save changes'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: rs.space(16)),

                      // Change password (email/password accounts only)
                      if (_isEmailPassword)
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(rs.space(16)),
                            child: Form(
                              key: _pwKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Change Password',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: _green,
                                      fontSize: rs.font(16),
                                    ),
                                  ),
                                  SizedBox(height: rs.space(12)),
                                  TextFormField(
                                    controller: _curPwCtrl,
                                    obscureText: _obCur,
                                    decoration: _deco(
                                      'Current password',
                                      icon: Icons.lock_outline,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obCur
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () =>
                                            setState(() => _obCur = !_obCur),
                                      ),
                                    ),
                                    style: TextStyle(fontSize: rs.font(14)),
                                    // Current password is optional for updateUser; keep for UX
                                  ),
                                  SizedBox(height: rs.space(12)),
                                  TextFormField(
                                    controller: _newPwCtrl,
                                    obscureText: _obNew,
                                    validator: _validatePassword,
                                    decoration: _deco(
                                      'New password',
                                      icon: Icons.lock,
                                    ).copyWith(
                                      helperText:
                                          'Min 8 chars, 1 a–z, 1 A–Z, 1 number',
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obNew
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () =>
                                            setState(() => _obNew = !_obNew),
                                      ),
                                    ),
                                    style: TextStyle(fontSize: rs.font(14)),
                                  ),
                                  SizedBox(height: rs.space(12)),
                                  TextFormField(
                                    controller: _confPwCtrl,
                                    obscureText: _obConf,
                                    validator: (v) {
                                      if (v != _newPwCtrl.text) {
                                        return 'Passwords do not match';
                                      }
                                      return null;
                                    },
                                    decoration: _deco(
                                      'Confirm new password',
                                      icon: Icons.lock_person,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obConf
                                              ? Icons.visibility
                                              : Icons.visibility_off,
                                        ),
                                        onPressed: () =>
                                            setState(() => _obConf = !_obConf),
                                      ),
                                    ),
                                    style: TextStyle(fontSize: rs.font(14)),
                                  ),
                                  SizedBox(height: rs.space(16)),
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: _green,
                                      foregroundColor: _gold,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _pwBusy ? null : _changePassword,
                                    icon: _pwBusy
                                        ? SizedBox(
                                            width: rs.space(18),
                                            height: rs.space(18),
                                            child:
                                                const CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.password),
                                    label: const Text('Update password'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else
                        Card(
                          elevation: 1,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Padding(
                            padding: EdgeInsets.all(rs.space(16)),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, color: _green),
                                SizedBox(width: rs.space(12)),
                                Expanded(
                                  child: Text(
                                    'Password is managed by your sign-in provider (Google/Apple).',
                                    style: TextStyle(
                                      color: _green,
                                      fontSize: rs.font(14),
                                    ),
                                  ),
                                ),
                              ],
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
