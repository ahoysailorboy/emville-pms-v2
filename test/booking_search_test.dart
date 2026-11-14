import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/features/bookings/data/booking_search.dart';
import 'support/mock_supabase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'Keywords match names, notes, source enums, references, numeric and extra fields',
      () {
    final booking = BookingRecord({
      'id': 'ref-OLD-42',
      'guest_name': "O'Neil Family",
      'notes': 'Courtyard wedding, vegetarian meals',
      'source': 'Booking.com',
      'status': 'enquiry',
      'total_price': 42000,
      'guest_email': 'family@example.com',
      'check_in': '2020-05-01',
      'check_out': '2020-05-10'
    });
    for (final query in [
      "O'NEIL",
      'courtyard',
      'booking.com',
      'old-42',
      '42000',
      '₹42,000',
      'family@example',
      'enquiry',
      '1 May 2020',
      'wedding vegetarian',
      'O\'Neil, wedding'
    ]) {
      expect(booking.matchesKeyword(query), isTrue, reason: query);
    }
    expect(booking.matchesKeyword('wedding nonexistent'), isFalse);
    expect(booking.matchesKeyword('%'), isFalse);
    expect(booking.matchesKeyword('  '), isTrue);
  });
  test(
      'Date range includes spanning stays, both boundaries, and the whole end date',
      () {
    final from = DateTime(2020, 5, 5), to = DateTime(2020, 5, 7);
    BookingRecord stay(String start, String end) =>
        BookingRecord({'check_in': start, 'check_out': end});
    for (final record in [
      stay('2020-05-01', '2020-05-10'),
      stay('2020-05-01', '2020-05-05'),
      stay('2020-05-07T23:59:00', '2020-05-08'),
      stay('2020-05-05', '2020-05-07')
    ]) {
      expect(record.overlaps(from: from, to: to), isTrue);
    }
    expect(
        stay('2020-05-01', '2020-05-04').overlaps(from: from, to: to), isFalse);
    expect(
        stay('2020-05-08', '2020-05-10').overlaps(from: from, to: to), isFalse);
    expect(stay('2020-05-01', '2020-05-10').overlaps(from: from), isTrue);
    expect(stay('2020-05-01', '2020-05-10').overlaps(to: to), isTrue);
  });
  test('All category retains old, distant-future and cancelled bookings', () {
    final now = DateTime(2026, 11, 14);
    final old = BookingRecord({
      'status': 'cancelled',
      'check_in': '2020-05-01',
      'check_out': '2020-05-10'
    });
    expect(old.inTab(BookingListTab.all, now), isTrue);
    expect(old.inTab(BookingListTab.upcoming, now), isFalse);
    final future = BookingRecord({
      'status': 'confirmed',
      'check_in': '2028-01-01',
      'check_out': '2028-01-03'
    });
    expect(future.inTab(BookingListTab.upcoming, now), isFalse);
    expect(future.inTab(BookingListTab.all, now), isTrue);
  });
  group('Repository', () {
    final backend = EmvilleTestBackend();
    setUpAll(backend.initialize);
    tearDownAll(() => Supabase.instance.dispose());
    test(
        'paginates beyond the old 200-result limit and the server default page',
        () async {
      backend.bookingRows = List.generate(
          1001,
          (i) => {
                'id': 'booking-$i',
                'guest_name': 'Guest $i',
                'check_in': '2020-01-01',
                'check_out': '2020-01-03',
                'status': 'confirmed'
              });
      final rows =
          await BookingSearchRepository(Supabase.instance.client).load();
      expect(rows.length, 1001);
      expect(rows.last.id, 'booking-1000');
      expect(backend.bookingReads.length, 3);
      expect(backend.bookingReads.map((r) => r.queryParameters['offset']),
          ['0', '500', '1000']);
      expect(
          backend.bookingReads.every((r) => r.queryParameters['select'] == '*'),
          isTrue);
      expect(backend.writes, isEmpty);
    });
  });
}
