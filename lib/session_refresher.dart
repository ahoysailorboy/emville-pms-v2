import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the Supabase session fresh when the app resumes.
class SessionRefresher with WidgetsBindingObserver {
  static SessionRefresher? _instance;

  SessionRefresher._();

  /// Call this once after Supabase.initialize()
  static void install() {
    _instance ??= SessionRefresher._().._init();
  }

  void _init() {
    WidgetsBinding.instance.addObserver(this);
    // Also check once on app start
    _refreshIfNeeded(forceIfExpired: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshIfNeeded();
    }
  }

  Future<void> _refreshIfNeeded({bool forceIfExpired = false}) async {
    final auth = Supabase.instance.client.auth;
    final session = auth.currentSession;
    if (session == null) return;

    final expSeconds = session.expiresAt; // int? (epoch seconds)
    if (expSeconds == null) return;

    // ✅ Convert epoch seconds → DateTime UTC
    final exp =
        DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000, isUtc: true);

    final now = DateTime.now().toUtc();
    final threshold = exp.subtract(const Duration(minutes: 2));

    if (forceIfExpired || now.isAfter(threshold)) {
      try {
        await auth.refreshSession();
      } on AuthException {
        // Refresh token might be revoked/expired
        await auth.signOut(scope: SignOutScope.local);
      }
    }
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
  }
}
