// lib/services/role_service.dart
import 'dart:developer';
import 'package:supabase_flutter/supabase_flutter.dart';

final _sb = Supabase.instance.client;

/// Returns the current user's role string (e.g. 'owner', 'admin', 'caretaker', 'super_admin')
/// or null if there is no signed-in user or no role row.
Future<String?> getCurrentUserRole() async {
  final user = _sb.auth.currentUser;
  if (user == null) {
    log('[role_service] no current user');
    return null;
  }

  try {
    final rows = await _sb
        .from('user_roles')
        .select('role')
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isNotEmpty) {
      final role = rows.first['role'] as String?;
      log('[role_service] role=$role for ${user.id}');
      return role;
    } else {
      log('[role_service] no role row for ${user.id}');
      return null;
    }
  } on PostgrestException catch (e, st) {
    log('[role_service] PostgrestException: ${e.message}', stackTrace: st);
    rethrow;
  } catch (e, st) {
    log('[role_service] unknown error: $e', stackTrace: st);
    rethrow;
  }
}

/// Convenience guard: true if user is owner/admin/super_admin.
Future<bool> isAdminOrOwner() async {
  final role = await getCurrentUserRole();
  return role == 'owner' || role == 'admin' || role == 'super_admin';
}
