// lib/services/user_bootstrap.dart
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// Ensures a row exists for the signed-in user in `public.users` with
/// (uid, email, full_name). Returns the role (if any) from `public.user_roles`.
Future<String?> ensureUserBootstrap() async {
  final user = _sb.auth.currentUser;
  if (user == null) {
    log('[bootstrap] No user.');
    return null;
  }

  // Derive a full name from metadata or fall back to email local-part.
  final meta = (user.userMetadata ?? const {});
  final fullName =
      (meta['full_name'] as String?) ??
      (meta['name'] as String?) ??
      (meta['fullName'] as String?) ??
      (user.email?.split('@').first ?? 'User');

  // Upsert into `public/users` (conflict target = uid).
  try {
    await _sb.from('users').upsert({
      'uid': user.id,
      'email': user.email,
      'full_name': fullName,
    }, onConflict: 'uid');
  } catch (e) {
    log('[bootstrap] users upsert failed: $e');
  }

  // Fetch role (if present) from `public.user_roles`.
  try {
    final row = await _sb
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id)
        .maybeSingle();

    log('[bootstrap] user_id=${user.id} roleRow=$row');
    final role = row?['role'] as String?;
    return role;
  } catch (e) {
    log('[bootstrap] fetch role failed: $e');
    return null;
  }
}
