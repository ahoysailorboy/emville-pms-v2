import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:emville_pms/responsive/responsive.dart';
import 'booking_new.dart';
import 'existing_booking.dart';
import 'booking_edit.dart';
import 'package:emville_pms/check_email.dart';
// TODO: Update this import to wherever you place the helper.
// e.g. import 'package:emville/core/supabase_call.dart';
import 'package:emville_pms/supabase_call.dart'
    show supabaseCall; // <-- adjust path

/// Emville brand colors
const Color _emGreen = Color(0xFF103329);
const Color _emGold = Color(0xFFD9A633);
const Color _emBg = Color(0xFFF7F6F3);

/// Booking status used for calendar coloring
enum BookingDayStatus { none, enquiry, confirmed, partial }

class BookingsHubPage extends StatefulWidget {
  const BookingsHubPage({super.key});

  @override
  State<BookingsHubPage> createState() => _BookingsHubPageState();
}

class _BookingsHubPageState extends State<BookingsHubPage> {
  DateTime _visibleMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _loading = true;

  /// Map of yyyy-mm-dd to status for quick lookup
  final Map<DateTime, BookingDayStatus> _dayStatus = {};

  @override
  void initState() {
    super.initState();
    _loadMonth(_visibleMonth);
  }

  Future<void> _loadMonth(DateTime anchor) async {
    setState(() => _loading = true);
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
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch calendar days: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goPrevMonth() {
    final prev = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
    setState(() => _visibleMonth = prev);
    _loadMonth(prev);
  }

  void _goNextMonth() {
    final next = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
    setState(() => _visibleMonth = next);
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

  Future<void> _onDayTap(
    BuildContext ctx,
    DateTime day,
    BookingDayStatus status,
  ) async {
    try {
      final supa = Supabase.instance.client;
      final items = await _fetchBookingsForDay(day); // your existing fetch

      String money(dynamic v) {
        if (v == null) return '₹ —';
        if (v is num) return '₹ ${v.toStringAsFixed(2)}';
        final parsed = double.tryParse('$v');
        return parsed == null ? '₹ —' : '₹ ${parsed.toStringAsFixed(2)}';
      }

      String asStr(dynamic v) =>
          (v == null || ('$v').trim().isEmpty) ? '—' : '$v';

      // ignore: use_build_context_synchronously
      await showDialog(
        // ignore: use_build_context_synchronously
        context: ctx,
        builder: (ctx) {
          final rs = ResponsiveSize.of(ctx);
          return AlertDialog(
            backgroundColor: _emGreen,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.radius(ctx, 15)),
            ),
            title: ResponsiveText(
              'Bookings for ${DateFormat('EEE, MMM d').format(day)}',
              style:
                  const TextStyle(fontWeight: FontWeight.w700, color: _emGold),
              fontSize: 18,
            ),
            content: SizedBox(
              width: (MediaQuery.of(ctx).size.width * 0.95)
                  .clamp(340.0, ResponsiveSize.panelMaxWidth(ctx)),
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: items.isEmpty
                  ? const ResponsiveText(
                      'No details found for this date.',
                      style: TextStyle(color: _emGreen),
                      fontSize: 15,
                    )
                  : StatefulBuilder(
                      builder: (context, setStateDialog) {
                        return Scrollbar(
                          thumbVisibility: true,
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                SizedBox(height: rs.h(14)),
                            itemBuilder: (_, i) {
                              final b = items[i] as Map<String, dynamic>;

                              final id = b['id'] as String?;
                              final status =
                                  (b['status'] as String?) ?? 'unknown';
                              final isEnquiry =
                                  status.toLowerCase() == 'enquiry';
                              final isFinalised =
                                  (b['finalised'] as bool?) == true;

                              final guestName = asStr(b['guest_name']);
                              final checkIn =
                                  DateTime.tryParse('${b['check_in']}');
                              final checkOut =
                                  DateTime.tryParse('${b['check_out']}');
                              final checkInStr = checkIn != null
                                  ? DateFormat('MMM d, yyyy').format(checkIn)
                                  : '—';
                              final checkOutStr = checkOut != null
                                  ? DateFormat('MMM d, yyyy').format(checkOut)
                                  : '—';

                              // Leading/summary row content of the tile
                              // ignore: unused_local_variable
                              final titleRow = Row(
                                children: [
                                  Expanded(
                                    child: ResponsiveText(
                                      guestName,
                                      style: const TextStyle(
                                        color: _emGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      fontSize: 15,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ResponsiveText(
                                    '$checkInStr → $checkOutStr',
                                    style: TextStyle(
                                      color: _emGreen.withValues(alpha: 0.8),
                                      fontWeight: FontWeight.w600,
                                    ),
                                    fontSize: 13,
                                  ),
                                ],
                              );

                              return Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius:
                                      BorderRadius.circular(R.radius(ctx, 12)),
                                  border: Border.all(
                                      color: _emGreen.withValues(alpha: 0.12)),
                                ),
                                child: Theme(
                                  data: Theme.of(ctx).copyWith(
                                    dividerColor: Colors.transparent,
                                    splashColor:
                                        _emGreen.withValues(alpha: 0.06),
                                    highlightColor:
                                        _emGreen.withValues(alpha: 0.04),
                                  ),
                                  child: ExpansionTile(
                                    tilePadding: EdgeInsets.symmetric(
                                      horizontal: rs.w(14),
                                      vertical: rs.h(6),
                                    ),
                                    childrenPadding: EdgeInsets.fromLTRB(
                                        rs.w(14), 0, rs.w(14), rs.h(12)),
                                    iconColor: _emGreen,
                                    collapsedIconColor: _emGreen,
                                    title: ResponsiveText(
                                      guestName,
                                      style: const TextStyle(
                                        color: _emGreen,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      fontSize: 15,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Padding(
                                      padding: EdgeInsets.only(top: rs.h(4)),
                                      child: ResponsiveText(
                                        'Status: ${status[0].toUpperCase()}${status.length > 1 ? status.substring(1) : ''}'
                                            .replaceAll('Unknown', '—'),
                                        style: TextStyle(
                                          color:
                                              _emGreen.withValues(alpha: 0.9),
                                          fontWeight: FontWeight.w600,
                                        ),
                                        fontSize: 13,
                                      ),
                                    ),

                                    // Expanded details
                                    children: [
                                      // Two-column-ish details
                                      _kv(ctx, 'Check in:', checkInStr),
                                      _kv(ctx, 'Check out:', checkOutStr),
                                      _kv(ctx, 'Number of persons:',
                                          asStr(b['no_of_pax'])),
                                      _kv(ctx, 'Booking Source:',
                                          asStr(b['source'])),
                                      _kv(ctx, 'Tariff:',
                                          money(b['total_price'])),
                                      _kv(ctx, 'Advance Paid:',
                                          money(b['advance_paid'])),
                                      _kv(ctx, 'Balance:', money(b['balance'])),
                                      SizedBox(height: rs.h(12)),
                                      const ResponsiveText(
                                        'Special Requests:',
                                        style: TextStyle(color: _emGreen),
                                        fontSize: 15,
                                      ),
                                      SizedBox(height: rs.h(10)),
                                      Container(
                                        width: double.infinity,
                                        constraints: BoxConstraints(
                                            minHeight: rs.h(100)),
                                        padding: EdgeInsets.all(rs.w(10)),
                                        decoration: BoxDecoration(
                                          color:
                                              _emGreen.withValues(alpha: 0.03),
                                          borderRadius: BorderRadius.circular(
                                              R.radius(ctx, 10)),
                                          border: Border.all(
                                              color: _emGreen.withValues(
                                                  alpha: 0.18)),
                                        ),
                                        child: ResponsiveText(
                                          (b['notes'] as String?)?.isNotEmpty ==
                                                  true
                                              ? (b['notes'] as String)
                                              : '—',
                                          style: TextStyle(
                                              color: _emGreen.withValues(
                                                  alpha: 0.9)),
                                          fontSize: 15,
                                        ),
                                      ),
                                      SizedBox(height: rs.h(14)),

                                      // Action row
                                      Row(
                                        children: [
                                          // Confirm (only if enquiry & not finalised)
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    isEnquiry && !isFinalised
                                                        ? _emGold
                                                        : Colors.grey.shade300,
                                                foregroundColor: _emGreen,
                                                padding: EdgeInsets.symmetric(
                                                    vertical: rs.h(12)),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          R.radius(ctx, 10)),
                                                ),
                                              ),
                                              onPressed: (isEnquiry &&
                                                      !isFinalised &&
                                                      id != null)
                                                  ? () async {
                                                      try {
                                                        await supa
                                                            .from(
                                                                'booking_details')
                                                            .update({
                                                          'status': 'confirmed',
                                                        }).eq('id', id);
                                                        // reflect locally
                                                        b['status'] =
                                                            'confirmed';
                                                        setStateDialog(() {});
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                  'Booking confirmed.'),
                                                            ),
                                                          );
                                                        }
                                                      } catch (e) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            SnackBar(
                                                              content: Text(
                                                                  'Failed to confirm: $e'),
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    }
                                                  : null,
                                              icon: const Icon(Icons.check),
                                              label: const ResponsiveText(
                                                'Confirm',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14),
                                              ),
                                            ),
                                          ),
                                          SizedBox(width: rs.w(10)),

                                          // Edit
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(
                                                    color: _emGreen.withValues(
                                                        alpha: 0.4)),
                                                foregroundColor: _emGreen,
                                                padding: EdgeInsets.symmetric(
                                                    vertical: rs.h(12)),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          R.radius(ctx, 10)),
                                                ),
                                              ),
                                              onPressed: (id == null)
                                                  ? null
                                                  : () async {
                                                      // Navigate to edit page
                                                      final changed =
                                                          await Navigator.of(
                                                                  context)
                                                              .push<bool>(
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              BookingEditPage(
                                                                  bookingId:
                                                                      id),
                                                        ),
                                                      );

                                                      // If something changed, re-fetch this row & refresh tile
                                                      if (changed == true) {
                                                        try {
                                                          final fresh = await supa
                                                              .from(
                                                                  'booking_details')
                                                              .select(
                                                                  'id, guest_name, status, check_in, check_out, no_of_pax, source, total_price, advance_paid, balance, notes, finalised')
                                                              .eq('id', id)
                                                              .maybeSingle();
                                                          if (fresh != null) {
                                                            items[i] = fresh;
                                                            setStateDialog(
                                                                () {});
                                                          }
                                                        } catch (_) {}
                                                      }
                                                    },
                                              icon: const Icon(Icons.edit),
                                              label: const ResponsiveText(
                                                'Edit',
                                                style: TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: _emGold, size: 28),
                label: const Text(
                  "Close",
                  style: TextStyle(
                    color: _emGold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load bookings: $e')),
      );
    }
  }

// Small detail row used in the expanded content
  Widget _kv(BuildContext ctx, String k, String v) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveSize.of(ctx).h(8)),
      child: Row(
        children: [
          ResponsiveText(
            k,
            style: const TextStyle(color: _emGreen),
            fontSize: 15,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: ResponsiveText(
              v,
              style: const TextStyle(
                color: _emGreen,
                fontWeight: FontWeight.w700,
              ),
              fontSize: 15,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return ResponsiveScaffold(
      backgroundColor: _emBg,
      appBar: AppBar(
        //backgroundColor: _emGreen,
        title: const ResponsiveText('Booking Hub',
            style: TextStyle(fontWeight: FontWeight.w700, color: _emGreen),
            fontSize: 18),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadMonth(_visibleMonth),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _ActionTiles(),
              SizedBox(height: rs.space(16)),
              _CalendarHeader(
                month: _visibleMonth,
                onPrev: _goPrevMonth,
                onNext: _goNextMonth,
              ),
              SizedBox(height: rs.space(8)),
              _CalendarGrid(
                month: _visibleMonth,
                dayStatus: _dayStatus,
                loading: _loading,
                onDayTap: (day, status) {
                  // fire-and-forget the async function; no await here
                  _onDayTap(context, day, status);
                },
              ),
              SizedBox(height: rs.space(12)),
              const _Legend(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTiles extends StatelessWidget {
  const _ActionTiles();

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return SizedBox(
      height: rs.h(150), // makes tiles square-ish; tweak as needed
      child: GridView.count(
        crossAxisCount: 3, // always 3 columns side by side
        physics: const NeverScrollableScrollPhysics(),
        childAspectRatio: 0.9, // square tiles
        shrinkWrap: true,
        mainAxisSpacing: rs.w(8),
        crossAxisSpacing: rs.w(8),
        children: [
          _HubTile(
            icon: Icons.add_box_outlined,
            title: 'New booking',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BookingNewPage()),
              );
            },
          ),
          _HubTile(
            icon: Icons.event_available_outlined,
            title: 'Existing bookings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExistingBookingPage()),
              );
            },
          ),
          _HubTile(
            icon: Icons.mark_email_unread_outlined,
            title: 'Check Email',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CheckEmailPage(),
                  settings: RouteSettings(arguments: {
                    "test_mode": true,
                    "message": "Manual launch of Check Email page",
                  }),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final tokens = R.tokens(context);

    return Material(
      color: Colors.white,
      elevation: 1,
      borderRadius: BorderRadius.circular(tokens.radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radius),
            border: Border.all(color: _emGreen.withValues(alpha: 0.12)),
          ),
          child: AspectRatio(
            aspectRatio: 0.9, // makes the tile square
            child: Padding(
              padding: EdgeInsets.all(rs.w(12)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: EdgeInsets.all(rs.w(10)),
                    decoration: BoxDecoration(
                      color: _emGreen,
                      borderRadius: BorderRadius.circular(rs.radius(12)),
                    ),
                    child:
                        Icon(icon, color: _emGold, size: R.icon(context, 28)),
                  ),
                  ResponsiveText(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _emGreen,
                    ),
                    fontSize: 14,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader(
      {required this.month, required this.onPrev, required this.onNext});
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  String _formatMonth(BuildContext context, DateTime m) {
    try {
      return DateFormat('MMMM yyyy').format(m);
    } catch (_) {
      const names = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      return '${names[m.month - 1]} ${m.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.radius(context, 16)),
        border: Border.all(color: _emGreen.withValues(alpha: 0.12)),
      ),
      padding: EdgeInsets.symmetric(horizontal: rs.w(12), vertical: rs.h(10)),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            color: _emGreen,
          ),
          Expanded(
            child: Center(
              child: ResponsiveText(
                _formatMonth(context, month),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _emGreen,
                ),
                fontSize: 18,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            color: _emGreen,
          ),
        ],
      ),
    );
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.dayStatus,
    required this.loading,
    this.onDayTap,
  });

  final DateTime month;
  final Map<DateTime, BookingDayStatus> dayStatus;
  final bool loading;
  final void Function(DateTime day, BookingDayStatus status)? onDayTap;

  List<DateTime> _buildDays(DateTime m) {
    final firstOfMonth = DateTime(m.year, m.month, 1);
    final startWeekday = firstOfMonth.weekday % 7; // make Sunday=0
    final daysBefore = startWeekday; // 0..6
    final start = firstOfMonth.subtract(Duration(days: daysBefore));

    final lastOfMonth = DateTime(m.year, m.month + 1, 0);
    final endWeekday = lastOfMonth.weekday % 7; // Sunday=0
    final daysAfter = 6 - endWeekday;

    final totalDays = (lastOfMonth.difference(start).inDays + 1) + daysAfter;
    return List.generate(
      totalDays,
      (i) => DateTime(start.year, start.month, start.day + i),
    );
  }

  BookingDayStatus _statusOf(DateTime d) {
    final k = DateTime(d.year, d.month, d.day);
    return dayStatus[k] ?? BookingDayStatus.none;
  }

  /// Occupied NIGHT rule:
  /// highlight a day `d` when `d` is booked AND `d+1` is booked.
  /// This paints [check_in .. check_out-1] (and excludes the checkout day).
  bool _highlightNight(DateTime d) {
    final today = _statusOf(d);
    if (today == BookingDayStatus.none) return false;
    final tomorrow = _statusOf(d.add(const Duration(days: 1)));
    return tomorrow != BookingDayStatus.none;
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final days = _buildDays(month);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.radius(context, 16)),
        border: Border.all(color: _emGreen.withValues(alpha: 0.12)),
      ),
      padding: EdgeInsets.symmetric(horizontal: rs.w(8), vertical: rs.h(12)),
      child: Column(
        children: [
          // Weekday headers
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: rs.w(6), vertical: rs.h(4)),
            child: Row(
              children: const [
                _WeekdayLabel('Sun'),
                _WeekdayLabel('Mon'),
                _WeekdayLabel('Tue'),
                _WeekdayLabel('Wed'),
                _WeekdayLabel('Thu'),
                _WeekdayLabel('Fri'),
                _WeekdayLabel('Sat'),
              ],
            ),
          ),
          SizedBox(height: rs.space(6)),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.15,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final d = days[index];
              final inMonth = d.month == month.month;
              final status = _statusOf(d);
              final highlight = _highlightNight(d); // ⟵ core change

              // Colors (use your palette only when highlighting nights)
              Color bg;
              Color border;
              switch (status) {
                case BookingDayStatus.confirmed:
                  bg = highlight
                      ? const Color.fromARGB(255, 31, 165, 78)
                      : Colors.white;
                  border = highlight
                      ? _emGreen.withValues(alpha: 0.4)
                      : _emGreen.withValues(alpha: 0.08);
                  break;
                case BookingDayStatus.enquiry:
                  bg = highlight
                      ? const Color.fromARGB(110, 210, 178, 14)
                      : Colors.white;
                  border = highlight
                      ? const Color.fromARGB(110, 210, 178, 14)
                      : _emGreen.withValues(alpha: 0.08);
                  break;
                case BookingDayStatus.partial:
                  bg = highlight
                      ? const Color.fromARGB(255, 28, 188, 190)
                      : Colors.white;
                  border = highlight
                      ? _emGreen.withValues(alpha: 0.4)
                      : _emGreen.withValues(alpha: 0.08);
                  break;
                case BookingDayStatus.none:
                  bg = Colors.white;
                  border = _emGreen.withValues(alpha: 0.08);
                  break;
              }

              final fg = _emGreen.withValues(alpha: inMonth ? 1 : 0.4);

              return Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(R.radius(context, 12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(R.radius(context, 12)),
                  onTap: inMonth
                      ? () => onDayTap?.call(
                          DateTime(d.year, d.month, d.day), status)
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius:
                          BorderRadius.circular(R.radius(context, 12)),
                      border: Border.all(color: border, width: 1),
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          top: rs.h(8),
                          left: rs.w(8),
                          child: ResponsiveText(
                            '${d.day}',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: fg,
                            ),
                            fontSize: 14,
                          ),
                        ),

                        // Optional: subtle dot for any booked (non-highlighted) day
                        if (!highlight && status != BookingDayStatus.none)
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: rs.w(6),
                              height: rs.w(6),
                              margin: EdgeInsets.only(bottom: rs.h(6)),
                              decoration: BoxDecoration(
                                color: _emGreen.withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),

                        if (!inMonth)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(
                                    R.radius(context, 12)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (loading) ...[
            SizedBox(height: rs.space(12)),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: ResponsiveText(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: _emGreen,
          ),
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Wrap(
      spacing: rs.w(14),
      runSpacing: rs.h(10),
      children: const [
        _LegendItem(
            color: Color.fromARGB(255, 31, 165, 78),
            border: _emGreen,
            label: 'Confirmed'),
        _LegendItem(
            color: Color.fromARGB(255, 28, 188, 190),
            border: _emGreen,
            label: 'Partial Booking'),
        _LegendItem(
            color: Color.fromARGB(110, 210, 178, 14),
            border: Color.fromARGB(110, 210, 178, 14),
            label: 'Enquiry'),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.border,
    required this.label,
  });

  final Color color;
  final Color border;
  final String label;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: rs.w(18),
          height: rs.h(18),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(R.radius(context, 6)),
          ),
        ),
        SizedBox(width: rs.w(8)),
        ResponsiveText(
          label,
          style: const TextStyle(
            color: _emGreen,
            fontWeight: FontWeight.w600,
          ),
          fontSize: 14,
        ),
      ],
    );
  }
}
