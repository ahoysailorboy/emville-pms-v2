import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/startup_screen.dart';
import 'package:emville_pms/features/auth/presentation/auth_gate.dart';
import 'package:emville_pms/features/home/presentation/home_shell.dart';
import 'package:emville_pms/features/accounts/presentation/main_accounts_page.dart';
import 'package:emville_pms/features/accounts/presentation/petty_cash_page.dart';
import 'package:emville_pms/features/accounts/presentation/approvals_page.dart';
import 'support/mock_supabase.dart';

/// Regenerate design previews with:
/// flutter test --update-goldens --dart-define=CAPTURE_DESIGN=true test/design_capture_test.dart
/// These fixture captures are opt-in because greetings and date labels follow the current date.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(() async {
    await backend.initialize();
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('Capture all approved screen layouts with fixture records',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 43, bottom: 14);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    Future<void> capture(String name) async {
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        await Future.wait([
          for (final asset in [
            Emville.logo,
            Emville.pool,
            Emville.bedroom,
            Emville.veranda
          ])
            precacheImage(AssetImage(asset), context)
        ]);
      });
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../design/flutter-previews/$name.png'));
    }

    Future<void> show(Widget home) async {
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false, theme: Emville.theme, home: home));
    }

    await show(const StartupScreen());
    await capture('startup');
    await show(const AuthGate());
    await tester.pumpAndSettle();
    await capture('login');
    await show(const SizedBox.shrink());
    await backend.signIn();
    await show(const HomeShell(role: 'owner'));
    await tester.pumpAndSettle();
    await capture('calendar');
    backend.bookingRows = [
      for (final row in <(String, int, int, int, int, String, String)>[
        ('Alex Morgan', 0, 2, 2, 4, 'confirmed', 'Direct'),
        ('Priya Nair', 4, 6, 1, 2, 'confirmed', 'Booking.com'),
        ('Daniel Reed', 7, 9, 2, 4, 'confirmed', 'AirBnB'),
        ('Maya Iyer', 11, 13, 1, 2, 'confirmed', 'Direct'),
        ('Ethan Cole', 14, 16, 2, 3, 'confirmed', 'Direct'),
        ('Sofia Ali', 17, 19, 1, 2, 'confirmed', 'Booking.com'),
        ('Maria Costa', 5, 8, 1, 2, 'enquiry', 'Direct'),
        ('Arjun Menon', 7, 9, 1, 2, 'enquiry', 'Direct')
      ])
        {
          'id': row.$1,
          'guest_name': row.$1,
          'check_in': backend.date(row.$2),
          'check_out': backend.date(row.$3),
          'no_of_rooms': row.$4,
          'no_of_pax': row.$5,
          'status': row.$6,
          'source': row.$7
        },
    ];
    await tester.tap(find.text('Bookings').last);
    await tester.pumpAndSettle();
    await capture('bookings');
    backend.bookingRows = null;
    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await capture('accounts');
    await tester.tap(find.text('Property').last);
    await tester.pumpAndSettle();
    await capture('maintenance');
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    await capture('reports');
    await show(const PettyCashPage());
    await tester.pumpAndSettle();
    await capture('petty-cash');
    await show(const MainAccountsPage());
    await tester.pumpAndSettle();
    await capture('main-ledger');
    await show(const ApprovalsPage());
    await tester.pumpAndSettle();
    await capture('approvals');
  }, skip: !const bool.fromEnvironment('CAPTURE_DESIGN'));
}
