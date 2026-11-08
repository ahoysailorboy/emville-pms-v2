import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'navigation.dart'; // provides rootNavigatorKey
import 'features/auth/presentation/auth_gate.dart';
import 'check_email.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    // Touch Supabase once to guarantee bootstrap ran before this widget.
    final _ = Supabase.instance.client;

    return MaterialApp(
      navigatorKey: rootNavigatorKey, // needed for deep-link navigation
      title: 'Emville PMS',
      debugShowCheckedModeBanner: false,
      onGenerateRoute: onGenerateAppRoute,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        useMaterial3: true,
      ),
      // Your normal entry
      home: const AuthGate(),

      // Deep-link target for OneSignal payloads
      routes: <String, WidgetBuilder>{
        '/check_email': (context) => const CheckEmailPage(),
      },
    );
  }
}
