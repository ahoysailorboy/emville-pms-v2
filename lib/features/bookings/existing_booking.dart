// lib/pages/existing_booking.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'booking_details.dart';
import 'bookings_advanced_search.dart';
// Responsive system
import 'package:emville_pms/responsive/responsive.dart';
//import 'package:your_app/responsive/responsive_text.dart';
//import 'package:your_app/responsive/responsive_extensions.dart';
//import 'package:your_app/responsive/responsive_size.dart';

// ---------- Config: adjust to match your schema ----------
const kBookingsTable = 'booking_details';
const kIdCol = 'id';
const kGuestNameCol = 'guest_name';
// Change to your date field if different (e.g., 'booking_date' or 'start_date')
const kBookingDateColumn = 'check_in';

// ---------- Emville color fallbacks (used if theme isn’t wired) ----------
const _emGreen = Color(0xFF103329);
const _emGold = Color(0xFFD9A633);

class ExistingBookingPage extends StatefulWidget {
  const ExistingBookingPage({super.key});

  @override
  State<ExistingBookingPage> createState() => _ExistingBookingPageState();
}

class _ExistingBookingPageState extends State<ExistingBookingPage> {
  late Future<_BookingBuckets> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchBuckets();
  }

  Future<void> _refresh() async {
    final next = _fetchBuckets();
    setState(() => _future = next);
    await next;
  }

  Future<_BookingBuckets> _fetchBuckets() async {
    // Local day bounds → UTC ISO for timestamptz comparisons
    final nowLocal = DateTime.now();
    final todayLocal = DateTime(nowLocal.year, nowLocal.month, nowLocal.day);

    final upcomingStart = todayLocal; // inclusive
    final upcomingEnd = todayLocal.add(const Duration(days: 30)); // inclusive
    final pastStart =
        todayLocal.subtract(const Duration(days: 30)); // inclusive
    final pastEnd = todayLocal.subtract(const Duration(days: 1)); // inclusive

    final supa = Supabase.instance.client;

    // Upcoming: [today .. today+30]
    final upcomingResp = await supa
        .from(kBookingsTable)
        .select('*') // ⬅️ no generics here
        .gte(kBookingDateColumn, upcomingStart.toUtc().toIso8601String())
        .lte(kBookingDateColumn, upcomingEnd.toUtc().toIso8601String())
        .order(kBookingDateColumn, ascending: true);

    // Past: [today-30 .. yesterday]
    final pastResp = await supa
        .from(kBookingsTable)
        .select('*') // ⬅️ no generics here
        .gte(kBookingDateColumn, pastStart.toUtc().toIso8601String())
        .lte(kBookingDateColumn, pastEnd.toUtc().toIso8601String())
        .order(kBookingDateColumn, ascending: false);

    // Supabase returns List<dynamic>; cast to Map<String, dynamic> for models
    final upcoming = (upcomingResp as List)
        .map((e) => _Booking.fromJson(e as Map<String, dynamic>))
        .toList();

    final past = (pastResp as List)
        .map((e) => _Booking.fromJson(e as Map<String, dynamic>))
        .toList();

    return _BookingBuckets(upcoming: upcoming, past: past);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    final rs = ResponsiveSize.of(context);

    final scheme = Theme.of(context).colorScheme;
    final emGreen = scheme.primary; // expect Emville green here
    final emGold = scheme.secondary; // expect Emville gold here
    // ignore: unused_local_variable
    final green = emGreen.computeLuminance().isNaN ? _emGreen : emGreen;
    final gold = emGold.computeLuminance().isNaN ? _emGold : emGold;

    return Scaffold(
      appBar: AppBar(
        title: const ResponsiveText(
          'Existing Bookings',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        backgroundColor: _emGreen,
        foregroundColor: _emGold,
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: RefreshIndicator(
          color: gold,
          onRefresh: _refresh,
          child: FutureBuilder<_BookingBuckets>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _ErrorState(
                  error: snap.error,
                  onRetry: _refresh,
                );
              }
              final buckets = snap.data ?? const _BookingBuckets.empty();

              return Column(
                children: [
                  SizedBox(height: R.space(context, 8)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: tokens.padding),
                    child: _SectionHeader(
                      title: 'Upcoming bookings',
                      color: _emGreen,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.padding,
                        vertical: R.space(context, 8),
                      ),
                      child: _DecoratedSection(
                        radius: tokens.radius,
                        child: _BookingList(
                          items: buckets.upcoming,
                          emptyText:
                              'No upcoming bookings in the next 30 days.',
                          onTap: (b) => _openDetails(b.id),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: tokens.padding),
                    child: _SectionHeader(
                      title: 'Past bookings',
                      color: _emGreen,
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.padding,
                        vertical: R.space(context, 8),
                      ),
                      child: _DecoratedSection(
                        radius: tokens.radius,
                        child: _BookingList(
                          items: buckets.past,
                          emptyText: 'No past bookings in the last 30 days.',
                          onTap: (b) => _openDetails(b.id),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      tokens.padding,
                      R.space(context, 8),
                      tokens.padding,
                      R.space(context, 16),
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: ResponsiveSize.panelMaxWidth(context),
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _emGold,
                            foregroundColor: _emGreen,
                            padding: EdgeInsets.symmetric(
                              vertical: rs.h(14),
                              horizontal: rs.w(12),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(tokens.radius),
                            ),
                            elevation: 1,
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BookingsAdvancedSearchPage()),
                            ); // TODO: Wire up advanced search later
                          },
                          icon: Icon(Icons.search, size: R.icon(context, 20)),
                          label: const ResponsiveText(
                            'Advanced Search',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _openDetails(String bookingId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookingDetailsPage(bookingId: bookingId),
      ),
    );
    // Later: replace with your real page
    // Navigator.pushNamed(context, '/booking-details', arguments: bookingId);
  }
}

// ---------- UI Bits ----------

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return ResponsiveText(
      title,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    );
  }
}

class _DecoratedSection extends StatelessWidget {
  final double radius;
  final Widget child;
  const _DecoratedSection({required this.radius, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: child,
      ),
    );
  }
}

class _BookingList extends StatelessWidget {
  final List<_Booking> items;
  final String emptyText;
  final void Function(_Booking) onTap;

  const _BookingList({
    required this.items,
    required this.emptyText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(R.space(context, 24)),
          child: ResponsiveText(
            emptyText,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final tokens = R.tokens(context);

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: R.space(context, 8)),
      itemCount: items.length,
      separatorBuilder: (_, __) => SizedBox(height: R.space(context, 6)),
      itemBuilder: (context, i) {
        final b = items[i];
        return Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.padding,
            vertical: R.space(context, 4),
          ),
          child: Card(
            elevation: 0,
            color: const Color(0xFFFAFAFA),
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: Color(0x11000000)),
              borderRadius: BorderRadius.circular(tokens.radius),
            ),
            child: ListTile(
              contentPadding: EdgeInsets.symmetric(
                horizontal: R.space(context, 16),
                vertical: R.space(context, 10),
              ),
              leading: CircleAvatar(
                radius: R.radius(context, 18),
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .primary
                    .withValues(alpha: 0.08),
                child: Icon(
                  Icons.event,
                  size: R.icon(context, 18),
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              title: ResponsiveText(
                b.guestName ?? 'Booking',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: _emGreen, // will be overridden by Theme if you prefer
                ),
              ),
              subtitle: ResponsiveText(
                _formatDate(b.date),
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 13,
                ),
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: R.icon(context, 20),
                color: Theme.of(context).colorScheme.primary,
              ),
              onTap: () => onTap(b),
            ),
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final fmt = DateFormat('EEE, d MMM yyyy');
    return fmt.format(date.toLocal());
  }
}

// ---------- Data layer ----------

class _Booking {
  final String id;
  final String? guestName;
  final DateTime date;

  _Booking({
    required this.id,
    required this.date,
    this.guestName,
  });

  factory _Booking.fromJson(Map<String, dynamic> json) {
    final id = json[kIdCol] as String;
    final guest = json[kGuestNameCol] as String?;
    final rawDate = json[kBookingDateColumn];

    final date = rawDate is String
        ? DateTime.parse(rawDate)
        : (rawDate is DateTime ? rawDate : DateTime.now());

    return _Booking(id: id, guestName: guest, date: date);
  }
}

class _BookingBuckets {
  final List<_Booking> upcoming;
  final List<_Booking> past;

  const _BookingBuckets({required this.upcoming, required this.past});
  const _BookingBuckets.empty()
      : upcoming = const [],
        past = const [];
}

// ---------- Placeholder booking details page ----------

// ---------- Error state ----------
class _ErrorState extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    final gold = Theme.of(context).colorScheme.secondary;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(R.space(context, 24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: R.icon(context, 36), color: Colors.redAccent),
            SizedBox(height: R.space(context, 12)),
            ResponsiveText(
              'Something went wrong.\n${error ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            SizedBox(height: R.space(context, 16)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    gold == const Color(0x00000000) ? _emGold : gold,
                foregroundColor:
                    green == const Color(0x00000000) ? _emGreen : green,
              ),
              onPressed: onRetry,
              child: const ResponsiveText(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
