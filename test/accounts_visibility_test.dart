import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/accounts/presentation/accounts_hub_page.dart';
import 'package:emville_pms/features/accounts/presentation/account_entry_page.dart';
import 'package:emville_pms/features/accounts/presentation/main_accounts_page.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(() async {
    await backend.initialize();
    await backend.signIn();
  });
  tearDownAll(() => Supabase.instance.dispose());
  for (final role in ['owner', 'admin', 'caretaker', 'user', 'super_admin']) {
    testWidgets('$role sees only permitted balance boxes and queries',
        (tester) async {
      backend.role = role;
      backend.reads.clear();
      final privileged = role == 'owner' || role == 'admin';
      await tester.pumpWidget(MaterialApp(
          theme: Emville.theme,
          home: const Scaffold(body: AccountsHubPage(role: 'owner'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('main-approved-balance')),
          privileged ? findsOneWidget : findsNothing);
      expect(
          find.byKey(const ValueKey('petty-approved-balance')), findsOneWidget);
      expect(find.text('Ledger balance'),
          privileged ? findsNWidgets(2) : findsNothing);
      expect(
          backend.reads.any((uri) => uri.path.endsWith('/main_ledger_balance')),
          privileged);
      final petty = backend.reads
          .where((uri) => uri.path.endsWith('/petty_cash_balance'));
      expect(
          petty.every((uri) =>
              uri.queryParameters['select']!.contains('ledger_balance') ==
              privileged),
          isTrue);
      if (privileged) {
        expect(find.textContaining('5,800'), findsOneWidget);
        expect(find.textContaining('450'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('Normal user opening main ledger never requests a balance',
      (tester) async {
    backend.role = 'caretaker';
    backend.reads.clear();
    await tester.pumpWidget(
        MaterialApp(theme: Emville.theme, home: const MainAccountsPage()));
    await tester.pumpAndSettle();
    expect(backend.reads.any((u) => u.path.endsWith('/main_ledger_balance')),
        isFalse);
    expect(
        backend.reads.where((u) => u.path.endsWith('/main_ledger')).every(
            (u) => !u.queryParameters['select']!.contains('account_balance')),
        isTrue);
    expect(tester.takeException(), isNull);
  });
  for (final kind in AccountEntryKind.values) {
    testWidgets(
        '$kind submits pending; funding writes exactly one main expense',
        (tester) async {
      tester.view.physicalSize = const Size(600, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      backend.role = 'owner';
      backend.writes.clear();
      backend.reads.clear();
      await tester.pumpWidget(MaterialApp(
          theme: Emville.theme,
          home: AccountEntryPage(kind: kind, receiver: 'Petty cash')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('account-entry-amount')), '5000');
      await tester.enterText(
          find.byKey(const ValueKey('account-entry-description')),
          'Test receipt');
      await tester.ensureVisible(find.text('Submit for approval'));
      await tester.tap(find.text('Submit for approval'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm submission'));
      await tester.pumpAndSettle();
      expect(backend.writes, hasLength(1));
      expect(backend.writes.single, contains('"transaction_status":"pending"'));
      expect(backend.writes.single, contains('"approved_by":null'));
      expect(
          backend.writes.single,
          contains(kind == AccountEntryKind.pettyReceipt
              ? '/petty_cash_ledger'
              : '/main_ledger'));
      expect(backend.reads.any((u) => u.path.endsWith('/main_ledger_balance')),
          isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
