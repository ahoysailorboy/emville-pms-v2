import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/bookings/existing_booking.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(() => Supabase.instance.dispose());
  setUp(() {
    backend.bookingReads.clear();
    backend.bookingRows = [
      {
        'id': 'old',
        'guest_name': "O'Neil Family",
        'notes': 'Courtyard wedding',
        'source': 'Booking.com',
        'status': 'confirmed',
        'check_in': '2020-05-01',
        'check_out': '2020-05-10',
        'no_of_rooms': 2,
        'no_of_pax': 4
      },
      {
        'id': 'end',
        'guest_name': 'End date guest',
        'notes': 'Late check-in',
        'source': 'AirBnB',
        'status': 'enquiry',
        'check_in': '2020-05-07T23:00:00',
        'check_out': '2020-05-09',
        'no_of_rooms': 1,
        'no_of_pax': 2
      },
      {
        'id': 'excluded',
        'guest_name': 'Outside period',
        'status': 'confirmed',
        'check_in': '2020-04-01',
        'check_out': '2020-05-04'
      },
      {
        'id': 'cancelled',
        'guest_name': 'Cancelled guest',
        'status': 'cancelled',
        'check_in': '2020-05-06',
        'check_out': '2020-05-07'
      },
    ];
  });
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
        MaterialApp(theme: Emville.theme, home: const ExistingBookingPage()));
    await tester.pumpAndSettle();
  }

  Future<void> chooseDate(WidgetTester tester, String key, String value) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to input'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, value);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Keyword search reaches old bookings and matches hidden fields without extra queries',
      (tester) async {
    await open(tester);
    final search = find.byKey(const ValueKey('booking-keyword-search'));
    expect(find.text("O'Neil Family"), findsNothing);
    await tester.enterText(search, 'courtyard');
    await tester.pumpAndSettle();
    expect(find.text('All bookings'), findsOneWidget);
    expect(find.text("O'Neil Family"), findsOneWidget);
    await tester.enterText(search, 'BOOKING.COM');
    await tester.pumpAndSettle();
    expect(find.text("O'Neil Family"), findsOneWidget);
    await tester.enterText(search, 'cancelled');
    await tester.pumpAndSettle();
    expect(find.text('Cancelled guest'), findsOneWidget);
    await tester.enterText(search, 'not-a-match');
    await tester.pumpAndSettle();
    expect(find.textContaining('No bookings match'), findsOneWidget);
    expect(backend.bookingReads.length, 1);
    expect(backend.writes, isEmpty);
  });
  testWidgets(
      'Date filter shows all overlapping bookings and combines with keyword search',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('booking-date-filter')));
    await tester.pumpAndSettle();
    await chooseDate(tester, 'booking-filter-from', '05/05/2020');
    await chooseDate(tester, 'booking-filter-to', '05/07/2020');
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(find.text('All bookings'), findsOneWidget);
    expect(find.text("O'Neil Family"), findsOneWidget);
    expect(find.text('End date guest'), findsOneWidget);
    expect(find.text('Cancelled guest'), findsOneWidget);
    expect(find.text('Outside period'), findsNothing);
    await tester.enterText(
        find.byKey(const ValueKey('booking-keyword-search')), 'wedding');
    await tester.pumpAndSettle();
    expect(find.text("O'Neil Family"), findsOneWidget);
    expect(find.text('End date guest'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('End date guest'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear date filter'));
    await tester.pumpAndSettle();
    expect(find.text('All bookings'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
