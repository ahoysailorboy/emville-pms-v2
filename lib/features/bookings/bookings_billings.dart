import 'booking_style.dart';
// lib/features/bookings/bookings_billings.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bookings_add_bill.dart';
import 'bookings_finalise_bill.dart';

// Responsive system

// Brand colors (explicit constants)
const emGreen = Color(0xFF103329);
const emGold = Color(0xFFD9A633);

// ---- Tables / columns ----
const kBookingsTable = 'booking_details';
const kBookingIdCol = 'id';
const kGuestNameCol = 'guest_name';
const kTotalPriceCol = 'total_price';
const kAdvancePaidCol = 'advance_paid';
const kSourceCol = 'source';
const kCheckInCol = 'check_in';
const kBalanceCol = 'balance';
const kCurrencyCol = 'currency';

const kExtrasTable = 'bookings_extras'; // ensure this matches your DB
const kExtrasBookingIdCol = 'booking_id';
const kExtrasTypeCol = 'bill_type'; // 'f&b' | 'other'
const kExtrasAmountCol = 'amount';
const kExtrasRemarksCol = 'remarks';
const kExtrasCreatedCol = 'created_at'; // sort by earliest first

class BookingsBillingPage extends StatefulWidget {
  final String bookingId;
  const BookingsBillingPage({super.key, required this.bookingId});

  @override
  State<BookingsBillingPage> createState() => _BookingsBillingPageState();
}

class _BookingsBillingPageState extends State<BookingsBillingPage> {
  late Future<_BillingData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadAll();
  }

  Future<_BillingData> _loadAll() async {
    final supa = Supabase.instance.client;

    // 1) Booking header (for title + accommodation details)
    final booking = await supa
        .from(kBookingsTable)
        .select(
          '$kBookingIdCol, $kGuestNameCol, $kTotalPriceCol, '
          '$kAdvancePaidCol, $kSourceCol, $kCheckInCol, $kBalanceCol, $kCurrencyCol',
        )
        .eq(kBookingIdCol, widget.bookingId)
        .maybeSingle();

    // 2) F&B list
    final fnbRaw = await supa
        .from(kExtrasTable)
        .select('$kExtrasAmountCol, $kExtrasRemarksCol, $kExtrasCreatedCol')
        .eq(kExtrasBookingIdCol, widget.bookingId)
        .eq(kExtrasTypeCol, 'f&b')
        .order(kExtrasCreatedCol, ascending: true);

    // 3) Misc list
    final miscRaw = await supa
        .from(kExtrasTable)
        .select('$kExtrasAmountCol, $kExtrasRemarksCol, $kExtrasCreatedCol')
        .eq(kExtrasBookingIdCol, widget.bookingId)
        .eq(kExtrasTypeCol, 'other')
        .order(kExtrasCreatedCol, ascending: true);

    final fnb = (fnbRaw as List)
        .map((e) => _ExtraItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final misc = (miscRaw as List)
        .map((e) => _ExtraItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return _BillingData(booking: booking, fnb: fnb, misc: misc);
  }

  Future<void> _addBill() async {
    final added = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => BookingsAddBillPage(bookingId: widget.bookingId)));
    if (added == true && mounted) {
      setState(() {
        _future = _loadAll();
      });
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_BillingData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final booking = data?.booking;
        final currency = booking?[kCurrencyCol]?.toString() ?? 'INR';
        final fnb = data?.fnb ?? <_ExtraItem>[];
        final misc = data?.misc ?? <_ExtraItem>[];
        final extras =
            [...fnb, ...misc].fold<num>(0, (sum, item) => sum + item.amount);
        final date = bookingDate(booking?[kCheckInCol]);
        Widget extrasCard(String title, String subtitle, IconData icon,
                List<_ExtraItem> items) =>
            BookingCard(children: [
              Row(children: [
                Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: Emville.sage,
                        borderRadius: BorderRadius.circular(9)),
                    child: Icon(icon, size: 17)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title, style: Emville.heading(19)),
                      const SizedBox(height: 5),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 10, color: Emville.muted))
                    ])),
                const SizedBox(width: 8),
                Text(
                    bookingMoney(
                        items.fold<num>(0, (s, e) => s + e.amount), currency),
                    style: const TextStyle(fontSize: 13))
              ]),
              const SizedBox(height: 15),
              const Divider(height: 1),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text('No items added yet.',
                    style: TextStyle(fontSize: 11, color: Emville.muted))
              else
                ...items.map((item) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookingValue(
                              item.remarks?.isNotEmpty == true
                                  ? item.remarks!
                                  : 'Bill',
                              bookingMoney(item.amount, currency)),
                          Text(
                              DateFormat('d MMM yyyy · h:mm a')
                                  .format(item.createdAt.toLocal()),
                              style: const TextStyle(
                                  fontSize: 9, color: Emville.muted)),
                          const SizedBox(height: 6)
                        ]))
            ]);
        return BookingFrame(
            title: 'Billing',
            subtitle: booking == null
                ? 'Review the charges for this stay.'
                : '${booking[kGuestNameCol] ?? 'Guest'}${date == null ? '' : ' · ${DateFormat('d MMM yyyy').format(date)}'}',
            actions: booking == null
                ? null
                : Row(children: [
                    Expanded(
                        child: OutlinedButton.icon(
                            onPressed: _addBill,
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add bill'))),
                    const SizedBox(width: 10),
                    Expanded(
                        child: FilledButton.icon(
                            onPressed: () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => BookingsFinaliseBillPage(
                                          bookingId: widget.bookingId)));
                              if (mounted) {
                                setState(() {
                                  _future = _loadAll();
                                });
                              }
                            },
                            icon: const Icon(Icons.check_circle_outline,
                                size: 16),
                            label: const Text('Finalise bill')))
                  ]),
            children: [
              if (snapshot.hasError)
                EmvilleError(onRetry: () async {
                  setState(() {
                    _future = _loadAll();
                  });
                })
              else if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (booking == null)
                const Center(child: Text('Booking not found.'))
              else ...[
                BookingBalance(
                    amount: (bookingNumber(booking[kBalanceCol]) ?? 0) + extras,
                    currency: currency,
                    detail:
                        'Room rent ${bookingMoney(booking[kTotalPriceCol], currency)} · Advance paid ${bookingMoney(booking[kAdvancePaidCol], currency)}'),
                bookingSection('Accommodation'),
                BookingCard(children: [
                  BookingValue('Room rent',
                      bookingMoney(booking[kTotalPriceCol], currency)),
                  BookingValue('Advance paid',
                      bookingMoney(booking[kAdvancePaidCol], currency)),
                  BookingValue(
                      'Booking source', booking[kSourceCol]?.toString() ?? '—')
                ]),
                const SizedBox(height: 18),
                extrasCard('Food & beverage', 'Meals, drinks and dining',
                    Icons.restaurant_outlined, fnb),
                const SizedBox(height: 13),
                extrasCard('Miscellaneous', 'Other charges for this stay',
                    Icons.receipt_long_outlined, misc),
                const SizedBox(height: 16),
                Text(
                    'All amounts in $currency. Review charges before finalising.',
                    style: const TextStyle(
                        fontSize: 10, height: 1.5, color: Emville.muted)),
              ]
            ]);
      });
}

// ---- Models ----

class _BillingData {
  final Map<String, dynamic>? booking;
  final List<_ExtraItem> fnb;
  final List<_ExtraItem> misc;

  _BillingData({required this.booking, required this.fnb, required this.misc});
}

class _ExtraItem {
  final num amount;
  final String? remarks;
  final DateTime createdAt;

  _ExtraItem({required this.amount, required this.createdAt, this.remarks});

  factory _ExtraItem.fromJson(Map<String, dynamic> json) {
    final amount = (json[kExtrasAmountCol] is num)
        ? json[kExtrasAmountCol] as num
        : num.tryParse('${json[kExtrasAmountCol]}') ?? 0;
    final createdRaw = json[kExtrasCreatedCol];
    final created = createdRaw is String
        ? DateTime.parse(createdRaw)
        : (createdRaw is DateTime ? createdRaw : DateTime.now());
    final remarks = (json[kExtrasRemarksCol] as String?)?.trim();
    return _ExtraItem(amount: amount, createdAt: created, remarks: remarks);
  }
}
