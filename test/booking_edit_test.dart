import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/bookings/booking_details.dart'
    show BookingDetailsPage;
import 'package:emville_pms/features/bookings/booking_edit.dart';
import 'package:emville_pms/features/home/presentation/home_shell.dart';
import 'package:emville_pms/features/bookings/booking_style.dart';
import 'package:emville_pms/features/bookings/data/booking_edit_repository.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = EmvilleTestBackend();
  Map<String, dynamic> row() => {
        'id': 'alex',
        'user_id': 'creator-id',
        'guest_name': 'Alex Morgan',
        'status': 'confirmed',
        'source': 'AirBnB',
        'property_id': 'Chelamattom',
        'no_of_rooms': 2,
        'no_of_pax': 4,
        'check_in': backend.date(4),
        'check_out': backend.date(6),
        'currency': 'INR',
        'total_price': 23000,
        'advance_paid': 11500,
        'advance_date': backend.date(-1),
        'balance': 11500,
        'finalised': false,
        'updated_at': '2026-11-01T12:00:00Z',
        'created_at': '2026-10-01T12:00:00Z',
        'confidence': null,
        'message_id': null,
        'notes': 'Original note',
        'stay_range': 'generated-range'
      };
  setUpAll(() async {
    await backend.initialize();
    await backend.signIn();
  });
  setUp(() {
    backend.bookingRows = [row()];
    backend.bookingUpdates.clear();
    backend.rejectBookingUpdate = false;
    backend.writes.clear();
    backend.reads.clear();
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> show(WidgetTester tester, Widget page,
      {double width = 390}) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false, theme: Emville.theme, home: page));
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, String field, String value) async {
    final finder = find.byKey(ValueKey('edit-$field'));
    await tester.scrollUntilVisible(finder, 160,
        scrollable: find.byType(Scrollable).first);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Save changes')));
    await tester.pumpAndSettle();
  }

  test('Patch excludes system fields, generated fields and unchanged values',
      () {
    final original = row();
    final values = {
      ...original,
      'guest_name': 'Updated',
      'total_price': 25000,
      'id': 'bad',
      'user_id': 'bad',
      'finalised': true,
      'confidence': 1,
      'message_id': 'bad',
      'created_at': 'bad',
      'updated_at': 'bad',
      'balance': 1,
      'stay_range': 'bad'
    };
    expect(bookingEditPatch(original, values),
        {'guest_name': 'Updated', 'total_price': 25000});
    expect(bookingEditPatch(original, {...original, 'advance_paid': 11500.0}),
        isEmpty);
  });
  test('Dates retain calendar values and timestamp instants', () {
    expect(serializeBookingDate(DateTime(2026, 12, 12), '2026-12-12'),
        '2026-12-12');
    final time = DateTime.parse('2026-12-12T12:30:00+05:30');
    expect(serializeBookingDate(time.toLocal(), '2026-12-12T07:00:00Z'),
        '2026-12-12T07:00:00.000Z');
    expect(
        bookingFieldEqual(
            'check_in', '2026-12-12T12:30:00+05:30', '2026-12-12T07:00:00Z'),
        isTrue);
  });
  test('Occupancy uses peak usage and frees rooms at checkout', () {
    final start = DateTime(2026, 12, 1), end = DateTime(2026, 12, 4);
    expect(
        availableBookingRooms([
          {
            'check_in': '2026-12-01',
            'check_out': '2026-12-02',
            'no_of_rooms': 2
          },
          {
            'check_in': '2026-12-02',
            'check_out': '2026-12-04',
            'no_of_rooms': 2
          }
        ], start, end),
        2);
    expect(
        availableBookingRooms([
          {
            'check_in': '2026-12-01',
            'check_out': '2026-12-03',
            'no_of_rooms': 2
          },
          {
            'check_in': '2026-12-02',
            'check_out': '2026-12-04',
            'no_of_rooms': 1
          }
        ], start, end),
        1);
  });
  test('Invalid dates, non-finite amounts and room counts are rejected', () {
    for (final patch in [
      {'check_out': backend.date(3)},
      {'total_price': double.nan},
      {'advance_paid': -1},
      {'no_of_rooms': 5},
      {'no_of_pax': 21},
      {'currency': 'bad!'}
    ]) {
      expect(() => validateBookingEdit(row(), patch),
          throwsA(isA<BookingEditException>()));
    }
  });
  test('Availability excludes this booking and guards against stale saves',
      () async {
    final repo = BookingEditRepository(Supabase.instance.client);
    await repo.save(row(), {'no_of_rooms': 4});
    expect(backend.writes, hasLength(1));
    final lookup = backend.reads.singleWhere((u) =>
        u.queryParameters['select'] == 'id,check_in,check_out,no_of_rooms');
    expect(lookup.queryParameters['id'], 'neq.alex');
    expect(lookup.queryParameters['property_id'], 'eq.Chelamattom');
    backend.rejectBookingUpdate = true;
    await expectLater(repo.save(row(), {'guest_name': 'Stale name'}),
        throwsA(isA<BookingEditException>()));
  });
  test(
      'Confirmed capacity conflicts block writes; enquiry edits remain allowed',
      () async {
    backend.bookingRows!.add({...row(), 'id': 'other', 'no_of_rooms': 4});
    final repo = BookingEditRepository(Supabase.instance.client);
    await expectLater(repo.save(row(), {'no_of_rooms': 3}),
        throwsA(isA<BookingEditException>()));
    expect(backend.writes, isEmpty);
    await repo.save(row(), {'status': 'enquiry', 'no_of_rooms': 3});
    expect(backend.writes, hasLength(1));
  });
  test(
      'All editable booking fields save together without touching technical fields',
      () async {
    final values = {
      ...row(),
      'guest_name': 'Changed Guest',
      'status': 'enquiry',
      'source': 'Instagram',
      'property_id': 'Updated property',
      'no_of_rooms': 4,
      'no_of_pax': 7,
      'check_in': backend.date(10),
      'check_out': backend.date(12),
      'currency': 'USD',
      'total_price': 100.50,
      'advance_paid': 50.25,
      'advance_date': backend.date(-2),
      'notes': 'Changed requests'
    };
    final patch = bookingEditPatch(row(), values);
    expect(patch.keys.toSet(), editableBookingFields);
    await BookingEditRepository(Supabase.instance.client).save(row(), patch);
    expect(backend.bookingUpdates['alex'], patch);
    expect(backend.writes, hasLength(1));
  });
  for (final width in [320.0, 390.0, 1024.0]) {
    testWidgets('Editor loads all booking fields and fits at $width',
        (tester) async {
      await show(tester, const BookingEditPage(bookingId: 'alex'),
          width: width);
      expect(find.text('Alex Morgan'), findsOneWidget);
      expect(find.byTooltip('Back'), findsOneWidget);
      expect(find.byKey(const ValueKey('edit-check_in-time')), findsNothing);
      for (final key in [
        'check_in',
        'check_out',
        'no_of_rooms',
        'property_id',
        'currency',
        'advance_date',
        'notes'
      ]) {
        await tester.scrollUntilVisible(find.byKey(ValueKey('edit-$key')), 140,
            scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      }
      expect(backend.writes, isEmpty);
    });
  }
  testWidgets(
      'Edit button opens editor; saving changed fields refreshes booking details',
      (tester) async {
    await show(tester, const BookingDetailsPage(bookingId: 'alex'));
    await tester.tap(find.text('Edit booking'));
    await tester.pumpAndSettle();
    await edit(tester, 'guest_name', 'Updated Guest');
    await edit(tester, 'total_price', '25000.50');
    await edit(tester, 'notes', 'Updated note');
    await save(tester);
    expect(find.text('Booking details'), findsOneWidget);
    expect(find.text('Updated Guest'), findsOneWidget);
    expect(backend.writes, hasLength(1));
    expect(backend.bookingUpdates['alex'], {
      'guest_name': 'Updated Guest',
      'total_price': 25000.50,
      'notes': 'Updated note'
    });
    expect(backend.writes.single, contains('/booking_details'));
    expect(tester.takeException(), isNull);
  });
  testWidgets('Back protects unsaved changes and discard writes nothing',
      (tester) async {
    await show(tester, const BookingDetailsPage(bookingId: 'alex'));
    await tester.tap(find.text('Edit booking'));
    await tester.pumpAndSettle();
    await edit(tester, 'guest_name', 'Unsaved');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingEditPage), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Booking details'), findsOneWidget);
    expect(backend.writes, isEmpty);
  });
  testWidgets(
      'Finalised booking edits retain the finalised flag and saved billing records',
      (tester) async {
    backend.bookingRows = [
      {...row(), 'finalised': true}
    ];
    await show(tester, const BookingDetailsPage(bookingId: 'alex'));
    await tester.tap(find.text('Edit booking'));
    await tester.pumpAndSettle();
    expect(find.textContaining('This booking has a finalised bill.'),
        findsOneWidget);
    await edit(tester, 'guest_name', 'Corrected Guest');
    await save(tester);
    expect(find.text('Booking details'), findsOneWidget);
    expect(backend.bookingUpdates['alex'], {'guest_name': 'Corrected Guest'});
    expect(backend.writes, hasLength(1));
  });
  testWidgets('Failed save keeps edits for retry', (tester) async {
    backend.rejectBookingUpdate = true;
    await show(tester, const BookingEditPage(bookingId: 'alex'));
    await edit(tester, 'guest_name', 'Retry Guest');
    await save(tester);
    expect(
        find.textContaining('This booking changed or is no longer editable.'),
        findsOneWidget);
    expect(find.text('Retry Guest'), findsOneWidget);
    expect(backend.writes, isEmpty);
  });
  testWidgets('Invalid numeric input never writes a booking', (tester) async {
    await show(tester, const BookingEditPage(bookingId: 'alex'));
    await edit(tester, 'total_price', 'NaN');
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Price and advance must be valid, non-negative amounts.'),
        findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(backend.writes, isEmpty);
  });
  testWidgets(
      'Calendar bookings open details directly and refresh after editing',
      (tester) async {
    backend.bookingRows = [
      {...row(), 'check_in': backend.date(0), 'check_out': backend.date(2)},
      {
        ...row(),
        'id': 'second',
        'guest_name': 'Second Guest',
        'check_in': backend.date(0),
        'check_out': backend.date(2)
      }
    ];
    await show(tester, const HomeShell(role: 'owner'));
    await tester.scrollUntilVisible(find.text('Second Guest'), 150,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Second Guest'));
    await tester.pumpAndSettle();
    expect(find.byType(BookingDetailsPage), findsOneWidget);
    expect(find.text('Second Guest'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Bookings for'), findsNothing);
    await tester.tap(find.text('Edit booking'));
    await tester.pumpAndSettle();
    await edit(tester, 'guest_name', 'Updated Calendar Guest');
    await save(tester);
    expect(find.text('Updated Calendar Guest'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Updated Calendar Guest'), 150,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Updated Calendar Guest'), findsOneWidget);
    expect(backend.bookingUpdates['second'],
        {'guest_name': 'Updated Calendar Guest'});
    expect(tester.takeException(), isNull);
  });
  testWidgets('Capture the booking editor with fixture data', (tester) async {
    await show(tester, const BookingEditPage(bookingId: 'alex'));
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(Emville.logo),
          tester.element(find.byType(MaterialApp)));
    });
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('../design/flutter-previews/edit-booking.png'));
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('edit-currency')), 160,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
            '../design/flutter-previews/edit-booking-payments.png'));
  }, skip: !const bool.fromEnvironment('CAPTURE_DESIGN'));
}
