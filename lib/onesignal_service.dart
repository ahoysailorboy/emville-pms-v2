import 'dart:io';
// ignore: unused_import
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../navigation.dart';

class OneSignalService {
  static const _appId = '038a16aa-124d-447f-8179-c36156e66d9d';

  static Future<void> init() async {
    // Permissions: iOS prompt only (Android auto).
    if (Platform.isIOS) {
      await OneSignal.Notifications.requestPermission(true);
    }

    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(_appId);

    // Foreground display: show system notif while app is open
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      // Keep default behavior: show it
      event.preventDefault();
      event.notification.display();
    });

    // Taps / clicks
    OneSignal.Notifications.addClickListener((event) {
      // Read your custom data (set it when sending)
      final data = event.notification.additionalData ?? {};
      final route = (data['route'] as String?) ?? 'check_email';

      _handleDeepLink(route, data);
    });

    // Save/refresh Player ID in Supabase
    final id = OneSignal.User.pushSubscription.id; // may be null initially
    if (id != null) {
      await _upsertPlayerId(id);
    }
    OneSignal.User.pushSubscription.addObserver((state) async {
      final newId = state.current.id;
      if (newId != null) {
        await _upsertPlayerId(newId);
      }
    });
  }

  static void _handleDeepLink(String route, Map<String, dynamic> data) {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    // If you want to support multiple routes later, expand this switch.
    switch (route) {
      case 'check_email':
        nav.pushNamed('/check_email', arguments: data);
        break;
      default:
        nav.pushNamed('/check_email', arguments: data);
    }
  }

  static Future<void> _upsertPlayerId(String playerId) async {
    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) return;

      // user_devices(user_id text, platform text, player_id text, updated_at timestamptz)
      await supa.from('user_devices').upsert({
        'user_id': user.id,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'player_id': playerId,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,platform');
    } catch (_) {
      // silently ignore; not fatal
    }
  }
}
