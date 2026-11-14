import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/report_options_page.dart';
import 'package:emville_pms/features/home/presentation/home_shell.dart';
import 'package:emville_pms/features/accounts/presentation/report_ledger_page.dart';
import 'package:emville_pms/features/accounts/presentation/report_income_page.dart';
import 'package:emville_pms/features/accounts/presentation/report_expenses_page.dart';
import 'package:emville_pms/features/accounts/presentation/report_petty_cash_page.dart';
import 'package:emville_pms/features/accounts/presentation/report_pl_page.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(() async {
    await backend.initialize();
    await backend.signIn();
  });
  setUp(() {
    backend.role = 'owner';
    backend.reads.clear();
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> show(WidgetTester tester, Widget page, double width) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false, theme: Emville.theme, home: page));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Four primary tabs keep the menu; secondary routes return to their originating tab',
      (tester) async {
    await show(tester, const HomeShell(role: 'owner'), 390);
    for (final tab in ['Home', 'Bookings', 'Accounts', 'Property']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Open menu'), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    }
    await tester.tap(find.text('Accounts').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsNothing);
    await tester.tap(find.text('Main ledger').last);
    await tester.pumpAndSettle();
    expect(find.text('Main ledger report'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Income trend'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Every rupee. Every receipt. In order.'), findsOneWidget);
    expect(find.byTooltip('Open menu'), findsOneWidget);
  });
  testWidgets('Every secondary drawer page exposes Back and restores Home',
      (tester) async {
    await show(tester, const HomeShell(role: 'owner'), 390);
    for (final title in [
      'Add maintenance task',
      'Maintenance reports',
      'Search maintenance',
      'My profile',
      'Edit maintenance tasks',
      'User management'
    ]) {
      await tester.tap(find.byTooltip('Open menu'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(title), 120,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Back'), findsOneWidget, reason: title);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome home, Anoop.'), findsOneWidget, reason: title);
      expect(tester.takeException(), isNull);
    }
    expect(backend.writes, isEmpty);
  });
  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('Report selectors retain filters and fit at $width',
        (tester) async {
      for (final page in <Widget>[
        const ReportLedgerPage(),
        const ReportIncomePage(),
        const ReportExpensesPage(),
        const ReportPettyCashPage(),
        const ReportPlPage()
      ]) {
        await tester.pumpWidget(const SizedBox.shrink());
        await show(tester, page, width);
        expect(find.byTooltip('Back'), findsOneWidget);
        expect(find.byTooltip('Open menu'), findsNothing);
        await tester.tap(find.text('Yearly (FY)'));
        await tester.pumpAndSettle();
        expect(find.text('Financial year'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (page is ReportPlPage) {
          await tester.tap(find.text('Quarterly'));
          await tester.pumpAndSettle();
          expect(find.text('Quarter'), findsOneWidget);
        } else {
          await tester.tap(find.text('From–To'));
          await tester.pumpAndSettle();
          expect(find.text('From'), findsOneWidget);
          expect(find.text('To'), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Pending'));
        await tester.tap(find.text('Pending'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('PDF'));
        await tester.tap(find.text('PDF'));
        await tester.pumpAndSettle();
        final options =
            tester.widget<ReportOptionsPage>(find.byType(ReportOptionsPage));
        expect(options.status, 'pending');
        expect(options.format, 'pdf');
        expect(tester.takeException(), isNull);
      }
      expect(
          backend.reads.any((u) =>
              u.path.endsWith('/main_ledger') ||
              u.path.endsWith('/petty_cash_ledger')),
          isFalse);
      expect(backend.writes, isEmpty);
    });
  }
  testWidgets(
      'Generating disables the controls and prevents duplicate export requests',
      (tester) async {
    final done = Completer<void>();
    var calls = 0;
    await show(
        tester,
        ReportOptionsPage(
            title: 'Report',
            period: 'monthly',
            periodLabels: const {'monthly': 'Monthly'},
            onPeriod: (_) {},
            dateSelection: const Text('November 2026'),
            status: 'approved',
            onStatus: (_) {},
            format: 'pdf',
            onFormat: (_) {},
            rangeSummary: 'November 2026',
            onGenerate: () {
              calls++;
              return done.future;
            }),
        390);
    await tester.tap(find.text('Generate report'));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Generating…'), findsOneWidget);
    final button = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Generating…'));
    expect(button.onPressed, isNull);
    done.complete();
    await tester.pumpAndSettle();
    expect(find.text('Generate report'), findsOneWidget);
  });
  testWidgets('Non-admins still cannot open the main ledger report',
      (tester) async {
    backend.role = 'caretaker';
    await show(tester, const ReportLedgerPage(), 390);
    expect(find.byType(ReportOptionsPage), findsNothing);
    expect(find.text('Only owners and admins can view main ledger balances.'),
        findsOneWidget);
  });
  testWidgets('Capture the restyled main ledger report selector',
      (tester) async {
    await show(tester, const ReportLedgerPage(), 390);
    await tester.tap(find.text('PDF'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(Emville.logo),
          tester.element(find.byType(MaterialApp)));
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../design/flutter-previews/report-options.png'));
  }, skip: !const bool.fromEnvironment('CAPTURE_DESIGN'));
}
