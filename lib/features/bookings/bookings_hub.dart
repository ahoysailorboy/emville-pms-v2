import 'package:emville_pms/features/reminders/home_reminders.dart';
import 'package:emville_pms/ui/emville_calendar.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'booking_new.dart';
import 'existing_booking.dart';
import 'booking_details.dart' show BookingDetailsPage;
import 'package:emville_pms/check_email.dart';
// TODO: Update this import to wherever you place the helper.
// e.g. import 'package:emville/core/supabase_call.dart';
import 'package:emville_pms/supabase_call.dart'
    show supabaseCall; // <-- adjust path

/// Booking status used for calendar coloring
enum BookingDayStatus { none, enquiry, confirmed, partial }

class BookingsHubPage extends StatefulWidget {
  const BookingsHubPage({super.key, this.embedded = false});
  final bool embedded;

  @override
  State<BookingsHubPage> createState() => _BookingsHubPageState();
}

class _BookingsHubPageState extends State<BookingsHubPage> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;
  bool _loadFailed = false;
  int _request = 0;
  int _reminderRefresh = 0;
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  late Future<List<dynamic>> _agenda;
  late Future<List<dynamic>> _today;

  /// Map of yyyy-mm-dd to status for quick lookup
  final Map<DateTime, BookingDayStatus> _dayStatus = {};

  @override
  void initState() {
    super.initState();
    _loadMonth(_visibleMonth);
    _today = _fetchBookingsForDay(_selectedDay);
    _agenda = _today;
  }

  Future<void> _loadMonth(DateTime anchor) async {
    final request = ++_request;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    final first = DateTime(anchor.year, anchor.month, 1);
    final nextMonth = DateTime(anchor.year, anchor.month + 1, 1);
    try {
      final client = Supabase.instance.client;

      final res = await supabaseCall(() async {
        return await client
            .from('booking_calendar_days')
            .select('day,status')
            .gte('day', first.toIso8601String())
            .lt('day', nextMonth.toIso8601String());
      });

      if (!mounted || request != _request) return;
      // Clear month slice, then rebuild
      _dayStatus.removeWhere((key, value) =>
          key.isAfter(first.subtract(const Duration(days: 1))) &&
          key.isBefore(nextMonth));

      for (final row in res as List<dynamic>) {
        final DateTime day = DateTime.parse(row['day']).toLocal();
        final String status = (row['status'] as String?) ?? 'unknown';
        final key = DateTime(day.year, day.month, day.day);
        final current = _dayStatus[key] ?? BookingDayStatus.none;
        // Priority: confirmed > enquiry > none
        if (status == 'confirmed') {
          _dayStatus[key] = BookingDayStatus.confirmed;
        } else if (status == 'enquiry' &&
            current != BookingDayStatus.confirmed) {
          _dayStatus[key] = BookingDayStatus.enquiry;
        } else {
          _dayStatus.putIfAbsent(key, () => BookingDayStatus.none);
        }
      }
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _loadFailed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _goPrevMonth() {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    setState(() {
      _visibleMonth = prev;
      _selectedDay = prev;
      _agenda = _fetchBookingsForDay(prev);
    });
    _loadMonth(prev);
  }

  void _goNextMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    setState(() {
      _visibleMonth = next;
      _selectedDay = next;
      _agenda = _fetchBookingsForDay(next);
    });
    _loadMonth(next);
  }

  /// Tap handler to fetch and show bookings for a specific day in a popup dialog
  Future<List<dynamic>> _fetchBookingsForDay(DateTime day) async {
    final client = Supabase.instance.client;

    // Build [dayStart, dayEnd)
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final rows = await supabaseCall(() async {
      return await client
          .from('booking_details')
          .select('''
          id,
          status,
          check_in,
          check_out,
          guest_name,
          no_of_pax,
          no_of_rooms,
          source,
          total_price,
          advance_paid,
          balance,
          currency,
          notes
        ''')
          // overlap condition: booking covers 'day'
          .lt('check_in', dayEnd.toIso8601String())
          .gte('check_out', dayStart.toIso8601String())
          .order('check_in', ascending: true);
    });

    return (rows as List<dynamic>);
  }

  Future<void> _refresh() async {
    setState(() {
      _reminderRefresh++;
      _today = _fetchBookingsForDay(DateUtils.dateOnly(DateTime.now()));
      _agenda = DateUtils.isSameDay(_selectedDay, DateTime.now())
          ? _today
          : _fetchBookingsForDay(_selectedDay);
    });
    await _loadMonth(_visibleMonth);
  }

  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => page,
        settings: page is CheckEmailPage
            ? const RouteSettings(arguments: {
                'test_mode': true,
                'message': 'Manual launch of Check Email page'
              })
            : null));
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] ??
            user?.userMetadata?['name'] ??
            user?.email?.split('@').first ??
            '')
        .toString()
        .trim()
        .split(' ')
        .first;
    final body = EmvilleBody(
        child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                children: [
                  Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          image: const DecorationImage(
                              image: AssetImage(Emville.pool),
                              fit: BoxFit.cover)),
                      child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(13),
                              gradient: const LinearGradient(colors: [
                                Color(0xEB113D32),
                                Color(0x70113D32)
                              ])),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('YOUR DAY AT EMVILLE',
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 10,
                                        letterSpacing: 2,
                                        color: Colors.white)),
                                const SizedBox(height: 8),
                                Text(
                                    name.isEmpty
                                        ? 'Welcome home.'
                                        : 'Welcome home, $name.',
                                    style: Emville.heading(27)
                                        .copyWith(color: Colors.white)),
                                const SizedBox(height: 8),
                                Text(
                                    DateFormat('EEEE, d MMMM yyyy')
                                        .format(DateTime.now()),
                                    style: const TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 11,
                                        color: Color(0xFFE5EADF))),
                              ]))),
                  FutureBuilder<List<dynamic>>(
                      future: _today,
                      builder: (context, snapshot) {
                        final today = DateUtils.dateOnly(DateTime.now());
                        final confirmed = (snapshot.data ?? [])
                            .where((row) => row['status'] == 'confirmed');
                        int rooms = 0, arrivals = 0, departures = 0;
                        for (final row in confirmed) {
                          final start = DateTime.tryParse(
                              row['check_in']?.toString() ?? '');
                          final end = DateTime.tryParse(
                              row['check_out']?.toString() ?? '');
                          if (start == null || end == null) continue;
                          if (DateUtils.isSameDay(start, today)) arrivals++;
                          if (DateUtils.isSameDay(end, today)) departures++;
                          if (!DateUtils.dateOnly(start).isAfter(today) &&
                              DateUtils.dateOnly(end).isAfter(today)) {
                            rooms += (row['no_of_rooms'] as num?)?.toInt() ?? 0;
                          }
                        }
                        return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 12),
                            child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  _stat(
                                      snapshot.hasData
                                          ? '$rooms / $kPropertyTotalRooms'
                                          : '—',
                                      'Rooms occupied'),
                                  _stat(snapshot.hasData ? '$arrivals' : '—',
                                      'Arrival today'),
                                  _stat(snapshot.hasData ? '$departures' : '—',
                                      'Departure today'),
                                ]));
                      }),
                  if (_loadFailed)
                    EmvilleError(
                        message: 'Could not load the booking calendar.',
                        onRetry: () => _loadMonth(_visibleMonth))
                  else
                    EmvilleCalendar(
                        month: _visibleMonth,
                        selectedDay: _selectedDay,
                        activity: _dayStatus.entries
                            .where((e) => e.value != BookingDayStatus.none)
                            .map((e) => e.key)
                            .toSet(),
                        loading: _loading,
                        onPrevious: _goPrevMonth,
                        onNext: _goNextMonth,
                        onSelected: (day) => setState(() {
                              _selectedDay = day;
                              _agenda = _fetchBookingsForDay(day);
                            })),
                  Padding(
                      padding: const EdgeInsets.fromLTRB(3, 14, 3, 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      DateFormat('EEEE, d MMMM')
                                          .format(_selectedDay),
                                      style: Emville.heading(19))),
                              if (DateUtils.isSameDay(
                                  _selectedDay, DateTime.now()))
                                const Text('Today',
                                    style: TextStyle(
                                        fontFamily: 'Roboto',
                                        fontSize: 10,
                                        color: Emville.muted))
                            ]),
                            FutureBuilder<List<dynamic>>(
                                future: _agenda,
                                builder: (context, snapshot) {
                                  if (snapshot.hasError) {
                                    return EmvilleError(
                                        message:
                                            'Could not load stays for this day.',
                                        onRetry: _refresh);
                                  }
                                  if (!snapshot.hasData) {
                                    return const Padding(
                                        padding: EdgeInsets.all(18),
                                        child: Center(
                                            child: SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))));
                                  }
                                  final rows = snapshot.data!
                                      .where((r) => r['status'] != 'cancelled')
                                      .toList();
                                  if (rows.isEmpty) {
                                    return const Padding(
                                        padding:
                                            EdgeInsets.symmetric(vertical: 19),
                                        child: Text(
                                            'No stays scheduled for this day.',
                                            style: TextStyle(
                                                fontFamily: 'Roboto',
                                                fontSize: 11,
                                                color: Emville.muted)));
                                  }
                                  return Column(
                                      children: rows.map((row) {
                                    final guest =
                                        row['guest_name']?.toString() ??
                                            'Guest';
                                    final initials = guest
                                        .split(' ')
                                        .where((s) => s.isNotEmpty)
                                        .take(2)
                                        .map((s) => s[0])
                                        .join();
                                    final start = DateTime.tryParse(
                                        row['check_in']?.toString() ?? '');
                                    final end = DateTime.tryParse(
                                        row['check_out']?.toString() ?? '');
                                    final status = row['status'] == 'enquiry'
                                        ? 'Enquiry'
                                        : DateUtils.isSameDay(
                                                start, _selectedDay)
                                            ? 'Arrival'
                                            : DateUtils.isSameDay(
                                                    end, _selectedDay)
                                                ? 'Departure'
                                                : 'In-house';
                                    return InkWell(
                                        onTap: row['id']
                                                    ?.toString()
                                                    .trim()
                                                    .isNotEmpty ==
                                                true
                                            ? () => _open(BookingDetailsPage(
                                                bookingId:
                                                    row['id'].toString()))
                                            : null,
                                        child: Padding(
                                            padding: const EdgeInsets.only(
                                                top: 16, bottom: 10),
                                            child: Row(children: [
                                              Container(
                                                  width: 42,
                                                  height: 42,
                                                  alignment: Alignment.center,
                                                  decoration: BoxDecoration(
                                                      color: Emville.sage,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              11)),
                                                  child: Text(initials,
                                                      style:
                                                          Emville.heading(15))),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(guest,
                                                        style: const TextStyle(
                                                            fontFamily:
                                                                'Roboto',
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)),
                                                    const SizedBox(height: 5),
                                                    Text(
                                                        '${row['no_of_rooms'] ?? '—'} rooms · ${start == null ? '—' : DateFormat('d').format(start)}–${end == null ? '—' : DateFormat('d MMM').format(end)} · ${row['no_of_pax'] ?? '—'} guests',
                                                        style: const TextStyle(
                                                            fontFamily:
                                                                'Roboto',
                                                            fontSize: 10,
                                                            color:
                                                                Emville.muted))
                                                  ])),
                                              const SizedBox(width: 6),
                                              EmvilleTag(status),
                                            ])));
                                  }).toList());
                                }),
                          ])),
                  HomeReminders(key: ValueKey(_reminderRefresh)),
                  const SizedBox(height: 20),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FilledButton(
                          onPressed: () => _open(const BookingNewPage()),
                          child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.add, size: 16),
                                SizedBox(width: 8),
                                Text('New booking')
                              ]))),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    TextButton(
                        onPressed: () => _open(const ExistingBookingPage()),
                        child: const Text('All bookings',
                            style:
                                TextStyle(fontFamily: 'Roboto', fontSize: 10))),
                    TextButton(
                        onPressed: () => _open(const CheckEmailPage()),
                        child: const Text('Booking email',
                            style:
                                TextStyle(fontFamily: 'Roboto', fontSize: 10)))
                  ]),
                ])));
    return widget.embedded ? body : EmvillePage(section: 0, child: body);
  }

  Widget _stat(String value, String label) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (label == 'Rooms occupied' && value.contains('/'))
          RichText(
              text: TextSpan(style: Emville.heading(24), children: [
            TextSpan(text: value.split('/').first.trim()),
            TextSpan(
                text: ' / ${value.split('/').last.trim()}',
                style: const TextStyle(
                    fontFamily: 'Roboto', fontSize: 10, color: Emville.muted))
          ]))
        else
          Text(value, style: Emville.heading(24)),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Roboto', fontSize: 10, color: Emville.muted)),
      ]);
}
