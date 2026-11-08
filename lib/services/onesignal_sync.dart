import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Keeps OneSignal user identity and role tags in sync with Supabase.
/// Call this after login, on session restore, and on logout.
Future<void> syncOneSignalIdentityAndRoleFromUsersV() async {
  final client = Supabase.instance.client;
  final user = client.auth.currentUser;

  // ────────────────────────────────────────────────────────────────
  // Handle signed-out state
  // ────────────────────────────────────────────────────────────────
  if (user == null) {
    await OneSignal.User.removeTags(['role', 'can_approve']);
    await OneSignal.logout();
    return;
  }

  // ────────────────────────────────────────────────────────────────
  // Attach device to Supabase user uid
  // ────────────────────────────────────────────────────────────────
  await OneSignal.login(user.id);

  // ────────────────────────────────────────────────────────────────
  // Fetch the role from public.users_v (enum: admin / owner / user)
  // ────────────────────────────────────────────────────────────────
  String role = 'user';
  try {
    final row = await client
        .from('users_v')
        .select('role')
        .eq('uid', user.id)
        .maybeSingle();

    final r = (row?['role'] ?? '').toString().trim().toLowerCase();
    if (r == 'admin' || r == 'owner' || r == 'user') {
      role = r;
    }
  } catch (e) {
    // default to user if lookup fails
    print('⚠️ Failed to fetch role from users_v: $e');
  }

  // ────────────────────────────────────────────────────────────────
  // Tag the device in OneSignal
  // ────────────────────────────────────────────────────────────────
  final isApprover = role == 'admin' || role == 'owner';
  await OneSignal.User.addTags({
    'role': role,
    'can_approve': isApprover ? '1' : '0',
  });

  print(
      '✅ OneSignal tagged with role=$role, can_approve=${isApprover ? 1 : 0}');
}
