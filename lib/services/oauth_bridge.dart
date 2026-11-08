// lib/services/oauth_bridge.dart
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _callbackScheme = 'io.supabase.emville';
const _callbackHost = 'login-callback';

/// Opens the provider in a browser sheet and exchanges the callback for a session.
/// Stores the session (so your AuthGate/onAuthStateChange will fire).
Future<void> oauthSignIn(OAuthProvider provider) async {
  final sb = Supabase.instance.client;

  // 1) Ask Supabase for the exact provider URL (includes PKCE, etc.)
  final urlRes = await sb.auth.getOAuthSignInUrl(
    provider: provider,
    redirectTo: '$_callbackScheme://$_callbackHost',
    // You can pass scopes/queryParams if needed:
    // scopes: 'email profile',
    // queryParams: {'prompt': 'select_account'},
  );

  // 2) Open the system auth sheet; it auto-closes on redirect back to your scheme.
  final callbackUrl = await FlutterWebAuth2.authenticate(
    url: urlRes.url,
    callbackUrlScheme: _callbackScheme,
  );

  // 3) Hand the callback to Supabase; it will store the session.
  // On your SDK this returns AuthSessionUrlResponse.
  await sb.auth.getSessionFromUrl(
    Uri.parse(callbackUrl),
    storeSession: true,
  );

  // No need to return anything; read sb.auth.currentSession or listen to onAuthStateChange.
}

/// Convenience helpers
Future<void> oauthGoogle() => oauthSignIn(OAuthProvider.google);
Future<void> oauthApple() => oauthSignIn(OAuthProvider.apple);
