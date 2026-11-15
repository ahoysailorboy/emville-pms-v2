import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // ✅ added

import 'services/onesignal_sync.dart';
import 'bootstrap.dart';
import 'app.dart';
import 'navigation.dart'; // for rootNavigatorKey
// ignore: unused_import
import 'check_email.dart'; // optional, for clarity

/// If a notification is tapped *very* early (before runApp),
/// we stash the payload here and handle it right after the first frame.
Map<String, dynamic>? _pendingRouteData;

Future<void> _initOneSignal() async {
  // Logging for setup only; returns void
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);

  // Initialize (void) — DO NOT await
  OneSignal.initialize('038a16aa-124d-447f-8179-c36156e66d9d');

  // iOS permission prompt (returns Future<bool>)
  final granted = await OneSignal.Notifications.requestPermission(true);
  debugPrint('🔔 OneSignal permission granted: $granted');

  // Inspect subscription
  final sub = OneSignal.User.pushSubscription;
  debugPrint('🆔 OneSignal playerId: ${sub.id}');
  debugPrint('📱 Push token present: ${sub.token != null}');
  debugPrint('✅ Opted in: ${sub.optedIn}');

  // Listen for changes
  OneSignal.User.pushSubscription.addObserver((state) {
    debugPrint('📡 Subscription changed: '
        'id=${state.current.id}, token=${state.current.token}, optedIn=${state.current.optedIn}');
  });

  // Foreground handler
  OneSignal.Notifications.addForegroundWillDisplayListener((event) {
    final n = event.notification;
    debugPrint('🔔 [FG] ${n.title} :: ${n.body} data=${n.additionalData}');
    // event.preventDefault(); // if you want to suppress the default alert
  });

  // Click/tap handler  ✅ route-aware navigation
  OneSignal.Notifications.addClickListener((event) {
    final data = Map<String, dynamic>.from(
      event.notification.additionalData ?? const <String, dynamic>{},
    );

    void _navigate(BuildContext? ctx) {
      if (ctx == null) return;
      final route = (data['route'] ?? '').toString();
      if (route == 'main_accounts_pending_approvals') {
        rootNavigatorKey.currentState?.pushNamed('/main/accounts/pending');
      } else if (route == 'petty_cash_pending_approvals') {
        rootNavigatorKey.currentState?.pushNamed('/petty-cash/pending');
      } else if (route == 'bank_reconciliation') {
        rootNavigatorKey.currentState?.pushNamed('/bank-reconciliation');
      } else if (route == 'work_reminder' || route == 'maintenance_task') {
        rootNavigatorKey.currentState?.pushNamed('/task', arguments: data);
      } else if (route == 'check_email') {
        // Prefer explicit message id if present
        final msgId = data['message_id'] ??
            data['gmail_message_id'] ??
            data['id']; // fallback
        rootNavigatorKey.currentState?.pushNamed(
          '/check_email',
          arguments: {
            if (msgId != null) 'message_id': msgId,
            ...data, // keep other keys if you rely on them elsewhere
          },
        );
      } else {
        // Fallback to previous behavior
        rootNavigatorKey.currentState
            ?.pushNamed('/check_email', arguments: data);
      }
    }

    final nav = rootNavigatorKey.currentState;
    if (nav != null) {
      _navigate(rootNavigatorKey.currentContext);
    } else {
      _pendingRouteData = data; // defer until after first frame
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await bootstrap(); // your existing env/Supabase/bootstrap
  await _initOneSignal(); // set up OneSignal before runApp

  // ✅ Sync OneSignal identity & tags (admins/owners) after init/login
  await syncOneSignalIdentityAndRoleFromUsersV();

  runApp(const App());

  // ✅ Keep tags updated on auth state changes (login/logout/switch)
  Supabase.instance.client.auth.onAuthStateChange.listen((_) async {
    await syncOneSignalIdentityAndRoleFromUsersV();
  });

  // If a notification was tapped before the app mounted, route now. ✅ route-aware
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final data = _pendingRouteData;
    _pendingRouteData = null;
    if (data != null) {
      final route = (data['route'] ?? '').toString();
      if (route == 'main_accounts_pending_approvals') {
        rootNavigatorKey.currentState?.pushNamed('/main/accounts/pending');
      } else if (route == 'petty_cash_pending_approvals') {
        rootNavigatorKey.currentState?.pushNamed('/petty-cash/pending');
      } else if (route == 'bank_reconciliation') {
        rootNavigatorKey.currentState?.pushNamed('/bank-reconciliation');
      } else if (route == 'work_reminder' || route == 'maintenance_task') {
        rootNavigatorKey.currentState?.pushNamed('/task', arguments: data);
      } else if (route == 'check_email') {
        final msgId =
            data['message_id'] ?? data['gmail_message_id'] ?? data['id'];
        rootNavigatorKey.currentState?.pushNamed(
          '/check_email',
          arguments: {
            if (msgId != null) 'message_id': msgId,
            ...data,
          },
        );
      } else {
        rootNavigatorKey.currentState
            ?.pushNamed('/check_email', arguments: data);
      }
    }
  });
}
