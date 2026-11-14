import 'package:emville_pms/ui/emville_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/auth/presentation/auth_gate.dart';
import 'package:emville_pms/features/home/presentation/home_shell.dart';
import 'package:emville_pms/features/accounts/presentation/approvals_page.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(backend.initialize);
  setUp(() async {
    backend.role = 'owner';
    backend.failCalendar = false;
    backend.removed.clear();
    backend.writes.clear();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets(
      'Signed-out screen preserves password visibility and sign-up access',
      (tester) async {
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await tester
        .pumpWidget(MaterialApp(theme: Emville.theme, home: const AuthGate()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back.'), findsOneWidget);
    final password = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(password).obscureText, isTrue);
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(tester.widget<TextField>(password).obscureText, isFalse);
    await tester.scrollUntilVisible(find.text('Create an account'), 120,
        scrollable: find.byType(Scrollable).first);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('Mockup structure and finance navigation fit at width $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
          theme: Emville.theme, home: const HomeShell(role: 'owner')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome home, Anoop.'), findsOneWidget);
      expect(find.text('Rooms occupied'), findsOneWidget);
      expect(find.text('3 / 4', findRichText: true), findsOneWidget);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('MON'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(find.byTooltip('Open menu')).dx,
          lessThan(width / 2));
      await tester.tap(find.text('Bookings').last);
      await tester.pumpAndSettle();
      expect(find.text('Upcoming stays'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Home').last);
      await tester.pumpAndSettle();
      expect(find.text('Welcome home, Anoop.'), findsOneWidget);
      await tester.tap(find.text('Accounts').last);
      await tester.pumpAndSettle();
      expect(
          find.text('Every rupee. Every receipt. In order.'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Main ledger'), 160,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Main ledger'));
      await tester.pumpAndSettle();
      expect(
          find.text('Receipts, payments and a balanced day.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Petty cash ledger'), 120,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Petty cash ledger'));
      await tester.pumpAndSettle();
      expect(find.text('Small expenses. Everything accounted for.'),
          findsOneWidget);
      expect(find.text('Bills'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Persistent navigation on a pushed finance page returns directly to the selected section.
      await tester.tap(find.text('Property').last);
      await tester.pumpAndSettle();
      expect(find.text('Planned maintenance'), findsOneWidget);
      expect(find.text('Your work plan'), findsOneWidget);
      await tester.tap(find.text('Upcoming').first);
      await tester.pumpAndSettle();
      expect(find.text('Pool filter service'), findsNothing);
      expect(find.text('Air conditioner service'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Open menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reports').last);
      await tester.pumpAndSettle();
      expect(find.text('Income trend'), findsOneWidget);
      expect(find.byType(GridView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Calendar selects a day and navigates to the next month',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme, home: const HomeShell(role: 'owner')));
    await tester.pumpAndSettle();
    final today = DateTime.now();
    await tester.tap(find.descendant(
        of: find.byType(EmvilleCalendar), matching: find.text('1')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EmvilleCalendar>(find.byType(EmvilleCalendar))
            .selectedDay,
        DateTime(today.year, today.month, 1));
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(tester.widget<EmvilleCalendar>(find.byType(EmvilleCalendar)).month,
        DateTime(today.year, today.month + 1));
    expect(backend.writes, isEmpty);
  });
  testWidgets('Failed calendar load shows retry and recovers', (tester) async {
    backend.failCalendar = true;
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme, home: const HomeShell(role: 'owner')));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the booking calendar.'), findsOneWidget);
    backend.failCalendar = false;
    await tester.tap(find.text('Try again').first);
    await tester.pumpAndSettle();
    expect(find.byType(EmvilleCalendar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Approval confirms, updates the selected ledger and removes the entry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme,
        home: const ApprovalsPage(initialFilter: 'Petty cash')));
    await tester.pumpAndSettle();
    expect(find.text('Fresh flowers'), findsOneWidget);
    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    expect(backend.writes, isEmpty);
    await tester.tap(find.text('Approve').last);
    await tester.pumpAndSettle();
    expect(backend.writes.single, contains('/petty_cash_ledger'));
    expect(backend.writes.single, contains('"transaction_status":"approved"'));
    expect(find.text('Fresh flowers'), findsNothing);
  });
  testWidgets('Caretaker can inspect approvals without approval controls',
      (tester) async {
    backend.role = 'caretaker';
    await tester.pumpWidget(
        MaterialApp(theme: Emville.theme, home: const ApprovalsPage()));
    await tester.pumpAndSettle();
    expect(find.text('Approve'), findsNothing);
    expect(find.text('View details'), findsWidgets);
    expect(backend.writes, isEmpty);
  });
}
