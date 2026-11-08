// lib/navigation.dart
import 'package:flutter/material.dart';

import 'check_email.dart';
import 'features/accounts/presentation/main_accounts_pending_approvals_page.dart';
import 'features/accounts/presentation/petty_cash_pending_approvals_page.dart';

/// Use this anywhere to push/pop on the root navigator.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

Route<dynamic>? onGenerateAppRoute(RouteSettings settings) {
  switch (settings.name) {
    case '/check_email':
    case '/check-email': // support both spellings
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const CheckEmailPage(),
      );

    case '/main/accounts/pending':
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const MainAccountPendingApprovalsPage(),
      );

    case '/petty-cash/pending':
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const PettyCashPendingApprovalsPage(),
      );

    default:
      return null; // let MaterialApp fall back to home/unknownRoute
  }
}
