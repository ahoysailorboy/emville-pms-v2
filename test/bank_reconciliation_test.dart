import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/accounts/reconciliation/bank_reconciliation_page.dart';
import 'package:emville_pms/features/accounts/reconciliation/statement_upload_page.dart';
import 'package:emville_pms/features/accounts/reconciliation/statement_review_page.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() async {
    backend.role = 'owner';
    backend.bankActions.clear();
    backend.bankTables.clear();
    await backend.signIn();
    backend.bankTables.addAll({
      'bank_reconciliations': [
        {
          'id': 'month-1',
          'month': '2026-10-01',
          'opening_balance': 10000,
          'closing_balance': 9750,
          'status': 'review',
          'file_path': 'private/test.pdf'
        }
      ],
      'bank_statement_lines': [
        {
          'id': 'line-1',
          'reconciliation_id': 'month-1',
          'line_number': 1,
          'date': '2026-10-03',
          'amount': 250,
          'transaction_type': 'expense',
          'description': 'Bank service fee',
          'reference': 'FEE123456',
          'state': 'unmatched'
        }
      ],
      'bank_reconciliation_proposals': [
        {
          'id': 'proposal-1',
          'line_id': 'line-1',
          'kind': 'missing',
          'amount': 250,
          'transaction_type': 'expense',
          'status': 'pending'
        }
      ],
      'bank_reconciliation_links': [],
      'bank_ledger_reviews': [],
      'bank_reconciliation_notes': [],
      'bank_ledger_reversal_proposals': [],
    });
  });
  Future<void> show(WidgetTester tester, Widget page,
      {double width = 390}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(debugShowCheckedModeBanner:false,theme: Emville.theme, home: page));
    await tester.pumpAndSettle();
  }

  test('Bank amounts use paise and reject malformed or overly precise values',
      () {
    expect(bankMoneyCents('1,23,456.78'), 12345678);
    expect(bankMoneyCents('-500.25', signed: true), -50025);
    expect(bankMoneyCents('100.001'), isNull);
    expect(bankMoneyCents('not money'), isNull);
    expect(bankMoneyCents('-50'), isNull);
  });
  testWidgets('Bank reconciliation is restricted to admins and owners',
      (tester) async {
    backend.role = 'user';
    await show(tester, const BankReconciliationPage());
    expect(
        find.text('Bank statements are available only to admins and owners.'),
        findsOneWidget);
    expect(find.text('Upload bank statement PDF'), findsNothing);
  });
  testWidgets(
      'Monthly reviews use the standard style and show PDF upload at narrow width',
      (tester) async {
    await show(tester, const BankReconciliationPage(), width: 320);
    expect(find.text('Bank reconciliation'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    await tester.ensureVisible(find.text('Upload bank statement PDF'));
    await tester.tap(find.text('Upload bank statement PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Choose PDF statement'), findsOneWidget);
    expect(find.text('Save & compare with ledger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Uploading without verified rows cannot create a reconciliation',
      (tester) async {
    await show(tester, const StatementUploadPage());
    await tester.ensureVisible(find.text('Save & compare with ledger'));
    await tester.tap(find.text('Save & compare with ledger'));
    await tester.pumpAndSettle();
    expect(backend.bankActions, isEmpty);
    expect(find.textContaining('review transactions'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'A ledger proposal requires an approval note and explicit confirmation before posting',
      (tester) async {
    await show(tester, const StatementReviewPage(id: 'month-1'));
    await tester.ensureVisible(find.text('Review proposal & approve'));
    await tester.tap(find.text('Review proposal & approve'));
    await tester.pumpAndSettle();
    expect(find.text('Approve & post entry?'), findsOneWidget);
    expect(backend.bankActions, isEmpty);
    await tester.tap(find.text('Approve & post'));
    await tester.pumpAndSettle();
    expect(backend.bankActions, isEmpty);
    await tester.enterText(
        find.byType(TextFormField).last, 'Checked against the bank statement');
    await tester.tap(find.text('Approve & post'));
    await tester.pumpAndSettle();
    expect(
        backend.bankActions.where((a) => a.startsWith('approve_bank_proposal')),
        hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Timing differences are recorded without posting ledger entries',
      (tester) async {
    await show(tester, const StatementReviewPage(id: 'month-1'));
    await tester
        .ensureVisible(find.text('Link existing entry / explain difference'));
    await tester.tap(find.text('Link existing entry / explain difference'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextFormField), 'Bank will process this next month');
    await tester.tap(find.text('Save review'));
    await tester.pumpAndSettle();
    expect(backend.bankActions, hasLength(1));
    expect(backend.bankActions.single, contains('resolve_bank_line'));
    expect(backend.bankActions.single, contains('timing'));
    expect(backend.writes.where((w) => w.contains('POST /rest/v1/main_ledger')),
        isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Capture bank reconciliation review with fixture data',
      (tester) async {
    await show(tester, const StatementReviewPage(id: 'month-1'));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(Emville.logo),
          tester.element(find.byType(MaterialApp)));
    });
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
            '../design/flutter-previews/bank-reconciliation.png'));
  }, skip: !const bool.fromEnvironment('CAPTURE_DESIGN'));
}
