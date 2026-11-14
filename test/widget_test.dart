import 'package:supabase_flutter/supabase_flutter.dart';
import 'support/mock_supabase.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/startup_screen.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/ui/ledger_panel.dart';
import 'package:emville_pms/features/accounts/presentation/generate_reports_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(() => Supabase.instance.dispose());
  testWidgets('Startup hands off to authentication content', (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme,
        home:
            const StartupGate(child: Scaffold(body: Text('Authentication')))));
    expect(find.text('Every stay.\nThoughtfully managed.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 901));
    expect(find.text('Authentication'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('Reports fit at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          MaterialApp(theme: Emville.theme, home: const GenerateReportsPage()));
      expect(find.text('From daily details to the bigger picture.'),
          findsOneWidget);
      await tester.scrollUntilVisible(find.text('Advanced filters'), 150,
          scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Ledger filters, searches and opens the selected entry',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var opened = false;
    final entries = Future.value([
      LedgerEntry(
          title: 'Guest deposit',
          date: '2026-11-14',
          amount: 2000,
          income: true,
          status: 'approved',
          onTap: () => opened = true),
      LedgerEntry(
          title: 'Garden supplies',
          date: '2026-11-13',
          amount: 150,
          income: false,
          status: 'pending',
          onTap: () {}),
    ]);
    await tester.pumpWidget(MaterialApp(
        theme: Emville.theme,
        home: LedgerPanel(
            title: 'Main ledger',
            period: 'Last 31 days',
            entries: entries,
            balance: const EmvilleBalance(
                label: 'Approved balance', amount: '₹1,850.00'),
            actions: const [],
            onRefresh: () async {})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('Guest deposit'), findsNothing);
    expect(find.text('Garden supplies'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.enterText(find.byType(TextField), 'deposit');
    await tester.pumpAndSettle();
    expect(find.text('Garden supplies'), findsNothing);
    await tester.tap(find.text('Guest deposit'));
    expect(opened, isTrue);
    expect(tester.takeException(), isNull);
  });
}
