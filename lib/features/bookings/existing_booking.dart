import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'booking_details.dart' show BookingDetailsPage;
import 'booking_new.dart' show BookingNewPage;
import 'data/booking_search.dart';

class ExistingBookingPage extends StatefulWidget {
  const ExistingBookingPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<ExistingBookingPage> createState() => _ExistingBookingPageState();
}

class _ExistingBookingPageState extends State<ExistingBookingPage> {
  final _search = TextEditingController();
  late final BookingSearchRepository _repository;
  late Future<List<BookingRecord>> _future;
  BookingListTab _tab = BookingListTab.upcoming;
  DateTime? _from, _to;
  bool get _hasDates => _from != null || _to != null;
  bool get _searching => _hasDates || _search.text.trim().isNotEmpty;
  @override
  void initState() {
    super.initState();
    _repository = BookingSearchRepository(Supabase.instance.client);
    _future = _repository.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _repository.load();
    });
    try {
      await _future;
    } catch (_) {}
  }

  void _queryChanged(String value) => setState(
      () => _tab = _searching ? BookingListTab.all : BookingListTab.upcoming);
  String _date(DateTime? date) =>
      date == null ? '—' : DateFormat('d MMM').format(date);
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) await _refresh();
  }

  Future<void> _filter() async {
    final selected = await showModalBottomSheet<_Dates>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Emville.ivory,
        builder: (sheetContext) {
          DateTime? from = _from, to = _to;
          return StatefulBuilder(builder: (context, update) {
            Future<void> pick(bool start) async {
              final first = start ? DateTime(1900) : from ?? DateTime(1900);
              final current = (start ? from : to) ?? from ?? DateTime.now();
              final initial = current.isBefore(first) ? first : current;
              final date = await showDatePicker(
                  context: context,
                  initialDate: initial,
                  firstDate: first,
                  lastDate: DateTime(2100, 12, 31));
              if (date == null || !context.mounted) return;
              update(() {
                if (start) {
                  from = date;
                  if (to != null && to!.isBefore(date)) to = date;
                } else {
                  to = date;
                }
              });
            }

            return SafeArea(
                child: SingleChildScrollView(
                    child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 8, 24,
                            24 + MediaQuery.viewInsetsOf(context).bottom),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Filter bookings',
                                  style: Emville.heading(27)),
                              const SizedBox(height: 9),
                              const Text(
                                  'Show every stay overlapping these dates. You can choose one or both dates.',
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 12,
                                      color: Emville.muted,
                                      height: 1.6)),
                              const SizedBox(height: 20),
                              const Text('From date',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 7),
                              OutlinedButton.icon(
                                  key: const ValueKey('booking-filter-from'),
                                  onPressed: () => pick(true),
                                  icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16),
                                  label: Text(from == null
                                      ? 'Choose from date'
                                      : DateFormat('d MMM yyyy')
                                          .format(from!))),
                              const SizedBox(height: 16),
                              const Text('To date',
                                  style: TextStyle(fontSize: 11)),
                              const SizedBox(height: 7),
                              OutlinedButton.icon(
                                  key: const ValueKey('booking-filter-to'),
                                  onPressed: () => pick(false),
                                  icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 16),
                                  label: Text(to == null
                                      ? 'Choose to date'
                                      : DateFormat('d MMM yyyy').format(to!))),
                              const SizedBox(height: 22),
                              Row(children: [
                                Expanded(
                                    child: OutlinedButton(
                                        onPressed: () =>
                                            Navigator.of(sheetContext)
                                                .pop(const _Dates(null, null)),
                                        child: const Text('Reset'))),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: FilledButton(
                                        onPressed: () =>
                                            Navigator.of(sheetContext)
                                                .pop(_Dates(from, to)),
                                        child: const Text('Apply filters')))
                              ]),
                            ]))));
          });
        });
    if (selected == null || !mounted) return;
    setState(() {
      _from = selected.from;
      _to = selected.to;
      _tab = _searching ? BookingListTab.all : BookingListTab.upcoming;
    });
  }

  void _clearDates() => setState(() {
        _from = null;
        _to = null;
        _tab = _searching ? BookingListTab.all : BookingListTab.upcoming;
      });

  @override
  Widget build(BuildContext context) {
    final body = EmvilleBody(
        child: Column(children: [
      Expanded(
          child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(13),
                            image: const DecorationImage(
                                image: AssetImage(Emville.pool),
                                fit: BoxFit.cover)),
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 19),
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(13),
                                gradient: const LinearGradient(colors: [
                                  Color(0xEB113D32),
                                  Color(0x70113D32)
                                ])),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('YOUR GUESTS AT EMVILLE',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 10,
                                          letterSpacing: 2,
                                          color: Colors.white)),
                                  const SizedBox(height: 8),
                                  Text('Bookings',
                                      style: Emville.heading(27)
                                          .copyWith(color: Colors.white)),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Every reservation. A thoughtful welcome.',
                                      style: TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 11,
                                          color: Color(0xFFE5EADF),
                                          height: 1.5)),
                                ]))),
                    FutureBuilder<List<BookingRecord>>(
                        future: _future,
                        builder: (context, snapshot) {
                          final all = snapshot.data;
                          final now = DateTime.now();
                          return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 15),
                              child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _stat(
                                        all == null
                                            ? '—'
                                            : '${all.where((b) => b.inTab(BookingListTab.upcoming, now)).length}',
                                        'Upcoming stays'),
                                    _stat(
                                        all == null
                                            ? '—'
                                            : '${all.where((b) => b.status == 'enquiry').length}',
                                        'Enquiries'),
                                    _stat(
                                        all == null
                                            ? '—'
                                            : '${all.where((b) => b.status == 'confirmed' && DateUtils.isSameDay(b.checkIn, now)).length}',
                                        'Arrival today'),
                                  ]));
                        }),
                    Row(children: [
                      Expanded(
                          child: SizedBox(
                              height: 41,
                              child: TextField(
                                  key: const ValueKey('booking-keyword-search'),
                                  controller: _search,
                                  onChanged: _queryChanged,
                                  style: const TextStyle(
                                      fontFamily: 'Roboto', fontSize: 11),
                                  decoration: InputDecoration(
                                      hintText: 'Search any keyword',
                                      prefixIcon:
                                          const Icon(Icons.search, size: 17),
                                      suffixIcon: _search.text.isEmpty
                                          ? null
                                          : IconButton(
                                              tooltip: 'Clear search',
                                              icon: const Icon(Icons.close,
                                                  size: 15),
                                              onPressed: () {
                                                _search.clear();
                                                _queryChanged('');
                                              }),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 11))))),
                      const SizedBox(width: 8),
                      SizedBox(
                          width: 41,
                          height: 41,
                          child: IconButton(
                              tooltip: 'Filter bookings by date',
                              key: const ValueKey('booking-date-filter'),
                              style: IconButton.styleFrom(
                                  backgroundColor:
                                      _hasDates ? Emville.sage : Emville.paper,
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      side: BorderSide(
                                          color: _hasDates
                                              ? const Color(0xFFB4C0A9)
                                              : Emville.line))),
                              onPressed: _filter,
                              icon: const Icon(Icons.tune, size: 19)))
                    ]),
                    if (_hasDates)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(children: [
                            Expanded(
                                child: Text(
                                    '${_from == null ? 'Any start' : DateFormat('d MMM yyyy').format(_from!)} – ${_to == null ? 'Any end' : DateFormat('d MMM yyyy').format(_to!)}',
                                    style: const TextStyle(
                                        fontSize: 10, color: Emville.muted))),
                            IconButton(
                                tooltip: 'Clear date filter',
                                onPressed: _clearDates,
                                icon: const Icon(Icons.close, size: 15),
                                visualDensity: VisualDensity.compact)
                          ])),
                    const SizedBox(height: 14),
                    EmvilleTabs(
                        labels: [
                          if (_searching) 'All',
                          'Upcoming',
                          'Past',
                          'Enquiries'
                        ],
                        selected: _label(_tab),
                        onSelected: (label) => setState(() => _tab =
                            BookingListTab.values
                                .firstWhere((t) => _label(t) == label))),
                    FutureBuilder<List<BookingRecord>>(
                        future: _future,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return EmvilleError(
                                onRetry: _refresh,
                                message:
                                    'Could not load bookings. Please try again.');
                          }
                          if (!snapshot.hasData) {
                            return const Padding(
                                padding: EdgeInsets.all(30),
                                child:
                                    Center(child: CircularProgressIndicator()));
                          }
                          final rows = snapshot.data!
                              .where((b) =>
                                  b.matchesKeyword(_search.text) &&
                                  b.overlaps(from: _from, to: _to) &&
                                  b.inTab(_tab, DateTime.now(),
                                      limitToRecent: !_searching))
                              .toList();
                          if (_tab == BookingListTab.past) {
                            rows.sort((a, b) => (b.checkOut ?? DateTime(1900))
                                .compareTo(a.checkOut ?? DateTime(1900)));
                          }
                          final period = _hasDates
                              ? 'Filtered period'
                              : _tab == BookingListTab.all
                                  ? 'All dates'
                                  : _tab == BookingListTab.upcoming
                                      ? 'Next 30 days'
                                      : _tab == BookingListTab.past
                                          ? 'Last 30 days'
                                          : 'Awaiting confirmation';
                          return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(3, 19, 3, 0),
                                    child: Row(children: [
                                      Expanded(
                                          child: Text(
                                              _tab == BookingListTab.all
                                                  ? 'All bookings'
                                                  : _tab ==
                                                          BookingListTab
                                                              .upcoming
                                                      ? 'Upcoming stays'
                                                      : _tab ==
                                                              BookingListTab
                                                                  .past
                                                          ? 'Past stays'
                                                          : 'Booking enquiries',
                                              style: Emville.heading(19))),
                                      const SizedBox(width: 8),
                                      Text('$period · ${rows.length}',
                                          style: const TextStyle(
                                              fontFamily: 'Roboto',
                                              fontSize: 10,
                                              color: Emville.muted))
                                    ])),
                                if (rows.isEmpty)
                                  const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 30),
                                      child: Text(
                                          'No bookings match your search.\nTry another keyword or date range.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                              fontFamily: 'Roboto',
                                              fontSize: 11,
                                              color: Emville.muted,
                                              height: 1.7))),
                                for (final booking in rows) _row(booking),
                                const Padding(
                                    padding: EdgeInsets.fromLTRB(3, 13, 3, 0),
                                    child: Text(
                                        'Select a stay to view guest details, payments and receipts.',
                                        style: TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 9,
                                            color: Emville.muted,
                                            height: 1.6))),
                              ]);
                        }),
                  ]))),
      Padding(
          padding: const EdgeInsets.fromLTRB(19, 8, 19, 10),
          child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(44, 43),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  onPressed: () => _open(const BookingNewPage()),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('New booking')))),
    ]));
    return widget.embedded ? body : EmvillePage(section: 1, child: body);
  }

  String _label(BookingListTab tab) => switch (tab) {
        BookingListTab.all => 'All',
        BookingListTab.upcoming => 'Upcoming',
        BookingListTab.past => 'Past',
        BookingListTab.enquiries => 'Enquiries'
      };
  Widget _stat(String number, String label) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(number, style: Emville.heading(24)),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(
                fontFamily: 'Roboto', fontSize: 10, color: Emville.muted))
      ]);
  Widget _row(BookingRecord booking) {
    final arrival = booking.status == 'confirmed' &&
        DateUtils.isSameDay(booking.checkIn, DateTime.now());
    final label = booking.status == 'enquiry'
        ? 'Enquiry'
        : booking.status == 'cancelled'
            ? 'Cancelled'
            : booking.inTab(BookingListTab.past, DateTime.now(),
                    limitToRecent: false)
                ? 'Completed'
                : arrival
                    ? 'Arrival today'
                    : booking.status == 'confirmed'
                        ? 'Confirmed'
                        : booking.status;
    return InkWell(
        onTap: () => _open(BookingDetailsPage(bookingId: booking.id)),
        child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 16),
            decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Emville.line))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 40,
                  height: 45,
                  decoration: BoxDecoration(
                      color: Emville.sage,
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            booking.checkIn == null
                                ? '—'
                                : DateFormat('d').format(booking.checkIn!),
                            style: Emville.heading(19)),
                        const SizedBox(height: 3),
                        Text(
                            booking.checkIn == null
                                ? ''
                                : DateFormat('MMM')
                                    .format(booking.checkIn!)
                                    .toUpperCase(),
                            style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 8,
                                letterSpacing: .8))
                      ])),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                          child: Text(booking.guest,
                              style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4))),
                      const Icon(Icons.chevron_right,
                          size: 15, color: Emville.muted)
                    ]),
                    const SizedBox(height: 5),
                    Text(
                        '${_date(booking.checkIn)}–${_date(booking.checkOut)} · ${booking.rooms} ${booking.rooms == '1' ? 'room' : 'rooms'} · ${booking.guests} guests',
                        style: const TextStyle(
                            fontFamily: 'Roboto',
                            fontSize: 10,
                            color: Emville.muted,
                            height: 1.5)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                              color: arrival
                                  ? Emville.forest
                                  : booking.status == 'enquiry'
                                      ? const Color(0xFFF3E8D2)
                                      : Emville.sage,
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(label,
                              style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 9,
                                  color: arrival
                                      ? Emville.paper
                                      : booking.status == 'enquiry'
                                          ? const Color(0xFF8A642E)
                                          : Emville.forest))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(booking.source,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 9,
                                  color: Emville.muted),
                              overflow: TextOverflow.ellipsis))
                    ])
                  ])),
            ])));
  }
}

class _Dates {
  const _Dates(this.from, this.to);
  final DateTime? from, to;
}
