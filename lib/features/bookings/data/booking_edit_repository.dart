import 'package:supabase_flutter/supabase_flutter.dart';

const bookingRoomCapacity = 4;
const editableBookingFields = <String>{
  'guest_name',
  'status',
  'check_in',
  'check_out',
  'no_of_pax',
  'no_of_rooms',
  'source',
  'property_id',
  'currency',
  'total_price',
  'advance_paid',
  'advance_date',
  'notes',
};
const bookingStatuses = ['confirmed', 'enquiry', 'cancelled', 'unknown'];
const bookingSources = ['AirBnB', 'Booking.com', 'Instagram', 'Other'];

class BookingEditException implements Exception {
  const BookingEditException(this.message);
  final String message;
  @override
  String toString() => message;
}

bool bookingDateOnly(Object? original) =>
    original == null || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch('$original');
String? serializeBookingDate(DateTime? value, Object? original) {
  if (value == null) return null;
  if (bookingDateOnly(original)) {
    return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
  }
  return value.toUtc().toIso8601String();
}

bool bookingFieldEqual(String field, dynamic a, dynamic b) {
  if (['check_in', 'check_out', 'advance_date'].contains(field)) {
    if (a == null || a == '') return b == null || b == '';
    final da = DateTime.tryParse('$a'), db = DateTime.tryParse('$b');
    return da != null && db != null && da.isAtSameMomentAs(db);
  }
  if (['total_price', 'advance_paid', 'no_of_pax', 'no_of_rooms']
      .contains(field)) {
    return (num.tryParse('${a ?? 0}') ?? 0) == (num.tryParse('${b ?? 0}') ?? 0);
  }
  return (a?.toString() ?? '').trim() == (b?.toString() ?? '').trim();
}

Map<String, dynamic> bookingEditPatch(
    Map<String, dynamic> original, Map<String, dynamic> values) {
  final patch = <String, dynamic>{};
  for (final field in editableBookingFields) {
    if (values.containsKey(field) &&
        !bookingFieldEqual(field, original[field], values[field])) {
      patch[field] = values[field];
    }
  }
  return patch;
}

void validateBookingEdit(
    Map<String, dynamic> original, Map<String, dynamic> values) {
  final row = {...original, ...values};
  for (final field in ['guest_name', 'property_id', 'source']) {
    if (row[field]?.toString().trim().isNotEmpty != true) {
      throw BookingEditException('Please enter ${field.replaceAll('_', ' ')}.');
    }
  }
  if (![...bookingStatuses, original['status']].contains(row['status'])) {
    throw const BookingEditException('Please select a booking status.');
  }
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(row['currency']?.toString() ?? '')) {
    throw const BookingEditException(
        'Use a three-letter currency code, such as INR.');
  }
  for (final entry
      in {'no_of_rooms': bookingRoomCapacity, 'no_of_pax': 20}.entries) {
    final n = int.tryParse('${row[entry.key]}');
    if (n == null || n < 1 || n > entry.value) {
      throw BookingEditException(
          '${entry.key == 'no_of_rooms' ? 'Rooms' : 'Guests'} must be between 1 and ${entry.value}.');
    }
  }
  for (final field in ['total_price', 'advance_paid']) {
    final n = num.tryParse('${row[field]}');
    if (n == null || !n.isFinite || n < 0) {
      throw const BookingEditException(
          'Price and advance must be valid, non-negative amounts.');
    }
  }
  final start = DateTime.tryParse('${row['check_in']}'),
      end = DateTime.tryParse('${row['check_out']}');
  if (start == null || end == null || !end.isAfter(start)) {
    throw const BookingEditException('Check-out must be after check-in.');
  }
  final advance = num.parse('${row['advance_paid']}');
  final paymentDate = DateTime.tryParse('${row['advance_date']}');
  final paymentChanged = !bookingFieldEqual(
          'advance_paid', original['advance_paid'], row['advance_paid']) ||
      !bookingFieldEqual(
          'advance_date', original['advance_date'], row['advance_date']);
  if (advance > 0 && paymentChanged && paymentDate == null) {
    throw const BookingEditException('Select the advance payment date.');
  }
  if (paymentDate != null && paymentChanged) {
    final now = DateTime.now(), local = paymentDate.toLocal();
    if (DateTime(local.year, local.month, local.day)
        .isAfter(DateTime(now.year, now.month, now.day))) {
      throw const BookingEditException(
          'Advance payment date cannot be in the future.');
    }
  }
}

/// Peak occupancy, rather than summing bookings that occupy different nights.
int availableBookingRooms(
    List<Map<String, dynamic>> rows, DateTime start, DateTime end) {
  final events = <(DateTime, int)>[];
  for (final row in rows) {
    final from = DateTime.tryParse('${row['check_in']}'),
        to = DateTime.tryParse('${row['check_out']}');
    if (from == null || to == null) {
      throw const BookingEditException(
          'Unable to verify room availability. Please try again.');
    }
    final a = from.isAfter(start) ? from : start,
        b = to.isBefore(end) ? to : end;
    if (!a.isBefore(b)) continue;
    final rooms = int.tryParse('${row['no_of_rooms']}') ?? bookingRoomCapacity;
    events.add((a, rooms));
    events.add((b, -rooms));
  }
  events.sort((a, b) {
    final time = a.$1.compareTo(b.$1);
    return time == 0 ? a.$2.compareTo(b.$2) : time;
  });
  var occupied = 0, peak = 0;
  for (final event in events) {
    occupied += event.$2;
    if (occupied > peak) peak = occupied;
  }
  return (bookingRoomCapacity - peak).clamp(0, bookingRoomCapacity);
}

class BookingEditRepository {
  BookingEditRepository(this.client);
  final SupabaseClient client;
  Future<Map<String, dynamic>?> load(String id) =>
      client.from('booking_details').select().eq('id', id).maybeSingle();

  Future<void> save(
      Map<String, dynamic> original, Map<String, dynamic> patch) async {
    if (client.auth.currentUser == null) {
      throw const BookingEditException('Please sign in again before saving.');
    }
    if (patch.isEmpty) return;
    if (patch.keys.any((key) => !editableBookingFields.contains(key))) {
      throw const BookingEditException('Only booking fields can be edited.');
    }
    final next = {...original, ...patch};
    validateBookingEdit(original, next);
    final id = original['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const BookingEditException('Booking not found.');
    }
    final reservationChanged = patch.keys.any([
      'status',
      'property_id',
      'check_in',
      'check_out',
      'no_of_rooms'
    ].contains);
    if (next['status'] == 'confirmed' && reservationChanged) {
      final start = DateTime.parse(next['check_in']),
          end = DateTime.parse(next['check_out']);
      final rows = <Map<String, dynamic>>[];
      const pageSize = 500;
      for (var offset = 0;; offset += pageSize) {
        final page = await client
            .from('booking_details')
            .select('id,check_in,check_out,no_of_rooms')
            .eq('property_id', next['property_id'])
            .eq('status', 'confirmed')
            .neq('id', id)
            .lt('check_in', end.toIso8601String())
            .gt('check_out', start.toIso8601String())
            .order('id')
            .range(offset, offset + pageSize - 1);
        rows.addAll(page);
        if (page.length < pageSize) break;
      }
      final available = availableBookingRooms(rows, start, end);
      if ((next['no_of_rooms'] as num) > available) {
        throw BookingEditException(
            'Only $available rooms are available for these dates. Change the dates, property or room count.');
      }
    }
    var query = client.from('booking_details').update(patch).eq('id', id);
    // Match the loaded revision so a stale form cannot overwrite a newer edit.
    if (original['updated_at'] != null) {
      query = query.eq('updated_at', original['updated_at']);
    }
    for (final field in patch.keys) {
      query = original[field] == null
          ? query.isFilter(field, null)
          : query.eq(field, original[field]);
    }
    query = original['finalised'] == null
        ? query.isFilter('finalised', null)
        : query.eq('finalised', original['finalised']);
    try {
      final saved = await query.select('id').maybeSingle();
      if (saved == null) {
        throw const BookingEditException(
            'This booking changed or is no longer editable. Reload it before saving.');
      }
    } on PostgrestException catch (error) {
      if (error.code == '23P01' || error.message.contains('no_overlapping')) {
        throw const BookingEditException(
            'These dates conflict with another confirmed booking. Please review room availability.');
      }
      rethrow;
    }
  }
}
