import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/bookings/booking_details.dart';
import 'package:emville_pms/features/bookings/bookings_billings.dart';
import 'package:emville_pms/features/bookings/bookings_add_bill.dart';
import 'package:emville_pms/features/bookings/bookings_finalise_bill.dart'
    show BookingsFinaliseBillPage;
import 'package:emville_pms/features/bookings/booking_style.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(() async {
    await backend.initialize();
    await backend.signIn();
  });
  setUp(() {
    backend.extras.clear();
    backend.writes.clear();
    backend.bookingRows = null;
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

  Future<void> capture(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('CAPTURE_DESIGN')) return;
    await tester.runAsync(() async {
      final context = tester.element(find.byType(MaterialApp));
      for (final asset in [Emville.pool, Emville.logo]) {
        await precacheImage(AssetImage(asset), context);
      }
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../design/flutter-previews/$name.png'));
  }

  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets(
        'Booking detail and billing layout, totals and navigation at $width',
        (tester) async {
      backend.extras.addAll([
        {
          'bill_type': 'f&b',
          'amount': 750.50,
          'remarks': 'Dinner',
          'created_at': backend.date(0)
        },
        {
          'bill_type': 'other',
          'amount': 200,
          'remarks': 'Transport',
          'created_at': backend.date(0)
        }
      ]);
      await show(tester, const BookingDetailsPage(bookingId: 'alex'), width);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.text('2 nights'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 390) await capture(tester, 'booking-details');
      await tester.tap(find.text('View billing'));
      await tester.pumpAndSettle();
      expect(find.text('Food & beverage'), findsOneWidget);
      expect(find.text('₹30,950.50'), findsOneWidget);
      expect(find.text('Dinner'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Transport'), 120,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Transport'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 390) {
        tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position
            .jumpTo(0);
        await tester.pumpAndSettle();
        await capture(tester, 'billing');
      }
      expect(backend.writes, isEmpty);
    });
    testWidgets('Add Bill and Finalise dialog fit and cancel safely at $width',
        (tester) async {
      await show(tester, const BookingsAddBillPage(bookingId: 'alex'), width);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (width == 390) await capture(tester, 'add-bill');
      await tester.pumpWidget(const SizedBox.shrink());
      await show(
          tester, const BookingsFinaliseBillPage(bookingId: 'alex'), width);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Finalise bill'), findsOneWidget);
      if (width == 390) await capture(tester, 'finalise-bill-popup');
      await tester.scrollUntilVisible(find.text('Continue'), 150,
          scrollable: find
              .descendant(
                  of: find.byType(Dialog), matching: find.byType(Scrollable))
              .first);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(backend.writes, isEmpty);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(backend.writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'Adding a bill preserves date, category, booking ID and amount then refreshes totals',
      (tester) async {
    await show(tester, const BookingsBillingPage(bookingId: 'alex'), 390);
    await tester.tap(find.text('Add bill').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bill-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('bill-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Food & beverage').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('bill-amount')), '1250.50');
    await tester.enterText(
        find.byKey(const ValueKey('bill-remarks')), 'Dinner service');
    await tester.tap(find.text('Add bill').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(backend.writes, hasLength(1));
    expect(backend.writes.single, contains('/bookings_extras'));
    expect(backend.extras.single['booking_id'], 'alex');
    expect(backend.extras.single['bill_type'], 'f&b');
    expect(backend.extras.single['amount'], 1250.50);
    expect(find.text('₹31,250.50'), findsOneWidget);
    expect(find.text('Dinner service'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Discounts update review; continuing does not save or create a ledger entry',
      (tester) async {
    backend.extras.add({
      'bill_type': 'f&b',
      'amount': 1000,
      'remarks': 'Dinner',
      'created_at': backend.date(0)
    });
    await show(tester, const BookingsFinaliseBillPage(bookingId: 'alex'), 390);
    await tester.enterText(find.byKey(const ValueKey('F&B (%)')), '10');
    await tester.ensureVisible(find.byKey(const ValueKey('finalise-payee')));
    await tester.enterText(
        find.byKey(const ValueKey('finalise-payee')), 'Alex Morgan');
    await tester.scrollUntilVisible(find.text('Continue'), 150,
        scrollable: find
            .descendant(
                of: find.byType(Dialog), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Review final bill'), findsOneWidget);
    expect(find.text('INR 900.00'), findsOneWidget);
    expect(backend.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Finalise rejects checkout before check-in without saving',
      (tester) async {
    backend.bookingRows = [
      {
        'id': 'alex',
        'guest_name': 'Alex Morgan',
        'check_in': backend.date(3),
        'check_out': backend.date(4),
        'currency': 'INR',
        'balance': 1000
      }
    ];
    await show(tester, const BookingsFinaliseBillPage(bookingId: 'alex'), 390);
    await tester.ensureVisible(find.byKey(const ValueKey('finalise-payee')));
    await tester.enterText(
        find.byKey(const ValueKey('finalise-payee')), 'Alex Morgan');
    await tester.scrollUntilVisible(find.text('Continue'), 150,
        scrollable: find
            .descendant(
                of: find.byType(Dialog), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Check-out cannot be before check-in.'), findsOneWidget);
    expect(find.byType(Dialog), findsOneWidget);
    expect(backend.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test(
      'Currency formatting retains cents and supports other booking currencies',
      () {
    expect(bookingMoney(1234.56, 'INR'), '₹1,234.56');
    expect(bookingMoney(12.50, 'USD'), 'USD 12.50');
  });
}
