import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/supabase_call.dart';

enum BookingListTab { all, upcoming, past, enquiries }

class BookingRecord {
  BookingRecord(Map<String, dynamic> row) : data = Map.unmodifiable(row);
  final Map<String, dynamic> data;
  String get id => data['id']?.toString() ?? '';
  String get guest => data['guest_name']?.toString().trim().isNotEmpty == true
      ? data['guest_name'].toString()
      : 'Guest';
  String get status => data['status']?.toString().toLowerCase() ?? 'unknown';
  String get source => data['source']?.toString() ?? '—';
  DateTime? get checkIn => _date(data['check_in']);
  DateTime? get checkOut => _date(data['check_out']) ?? checkIn;
  String get rooms => data['no_of_rooms']?.toString() ?? '—';
  String get guests => data['no_of_pax']?.toString() ?? '—';
  static DateTime? _date(dynamic raw) =>
      DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
  static DateTime day(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  // Every returned field is searchable as text, including enum and numeric values.
  // This avoids ILIKE errors on enum columns and never interpolates user input into SQL filters.
  late final String _searchText = [
    ...data.values.map((v) => v?.toString() ?? ''),
    for (final date in [checkIn, checkOut])
      if (date != null) ...[
        DateFormat('d MMM yyyy').format(date),
        DateFormat('d MMMM yyyy').format(date),
      ],
  ].join(' ').toLowerCase();

  bool matchesKeyword(String query) {
    final terms = query
        .toLowerCase()
        .replaceAll('₹', '')
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty);
    return terms.every(_searchText.contains);
  }

  /// Inclusive calendar-day overlap, matching the advanced search's overlap rule.
  /// Includes a stay starting earlier or ending later than the selected period.
  bool overlaps({DateTime? from, DateTime? to}) {
    if (from == null && to == null) return true;
    final start = checkIn, end = checkOut;
    if (start == null || end == null) return false;
    return (from == null || !day(end).isBefore(day(from))) &&
        (to == null || !day(start).isAfter(day(to)));
  }

  bool inTab(BookingListTab tab, DateTime now, {bool limitToRecent = true}) {
    final today = day(now), start = checkIn, end = checkOut;
    if (tab == BookingListTab.all) return true;
    if (tab == BookingListTab.enquiries) return status == 'enquiry';
    if (start == null ||
        end == null ||
        status == 'enquiry' ||
        status == 'cancelled' ||
        status == 'unknown') {
      return false;
    }
    if (tab == BookingListTab.upcoming) {
      return !day(start).isBefore(today) &&
          (!limitToRecent ||
              day(start).isBefore(today.add(const Duration(days: 31))));
    }
    return !day(end).isAfter(today) &&
        (limitToRecent
            ? !day(end).isBefore(today.subtract(const Duration(days: 30)))
            : true);
  }
}

class BookingSearchRepository {
  BookingSearchRepository(this.client);
  final SupabaseClient client;
  static const pageSize = 500;
  Future<List<BookingRecord>> load() async {
    final records = <BookingRecord>[];
    // Read all accessible pages: keyword/date searches must not silently stop at
    // the old 30-day window or advanced search's 200-result cap.
    for (var offset = 0;; offset += pageSize) {
      final rows = await supabaseCall(() => client
          .from('booking_details')
          .select('*')
          .order('check_in')
          .order('id')
          .range(offset, offset + pageSize - 1));
      records.addAll(rows.map(BookingRecord.new));
      if (rows.length < pageSize) break;
    }
    return records;
  }
}
