// lib/features/bookings/bookings_billings.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'bookings_add_bill.dart';
import 'bookings_finalise_bill.dart';

// Responsive system
import 'package:emville_pms/responsive/responsive_theme.dart';
import 'package:emville_pms/responsive/responsive_text.dart';
import 'package:emville_pms/responsive/responsive_size.dart';

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

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    final titleDateFmt = DateFormat('d MMM yyyy');

    return FutureBuilder<_BillingData>(
      future: _future,
      builder: (context, snap) {
        final loading = snap.connectionState == ConnectionState.waiting;
        final error = snap.hasError ? snap.error : null;
        final data = (!loading && error == null) ? snap.data : null;

        final guestName = data?.booking?[kGuestNameCol] as String? ?? 'Billing';
        final checkInRaw = data?.booking?[kCheckInCol];
        final checkIn = _parseDate(checkInRaw);
        final titleText = checkIn != null
            ? '$guestName • ${titleDateFmt.format(checkIn.toLocal())}'
            : guestName;

        return Scaffold(
          appBar: AppBar(
            backgroundColor: emGreen,
            foregroundColor: Colors.white,
            title: ResponsiveText(
              titleText,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          backgroundColor: const Color(0xFFF7F7F7),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                if (loading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (error != null) {
                  return _ErrorState(
                    error: error,
                    onRetry: () async => setState(() => _future = _loadAll()),
                  );
                }

                final booking = data!.booking;
                final fnb = data.fnb;
                final misc = data.misc;

                final total = booking?[kTotalPriceCol];
                final advance = booking?[kAdvancePaidCol];
                final source = booking?[kSourceCol] as String?;
                final currency = booking?[kCurrencyCol] as String?;

                // Balance to be paid = booking_details.balance + sum(extras.amount)
                final bookingBalance = _asNum(booking?[kBalanceCol]) ?? 0;
                final extrasTotal = fnb.fold<num>(0, (s, e) => s + e.amount) +
                    misc.fold<num>(0, (s, e) => s + e.amount);
                final balanceToBePaid = bookingBalance + extrasTotal;

                return Column(
                  children: [
                    // --- Accommodation (no internal scroll) ---
                    Padding(
                      padding: EdgeInsets.all(tokens.padding),
                      child: _SectionCard(
                        title: 'Accommodation',
                        child: Column(
                          children: [
                            _BillRow(
                              label: 'Room Rent',
                              value: _fmtMoney(total, currency),
                            ),
                            _BillRow(
                              label: 'Advance Paid',
                              value: _fmtMoney(advance, currency),
                            ),
                            _BillRow(
                              label: 'Booking source',
                              value: source ?? '—',
                            ),
                            _BillRow(
                              label: 'Balance to be paid',
                              value: _fmtMoney(balanceToBePaid, currency),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- F&B Bills (scroll inside the section) ---
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: tokens.padding),
                      child: const _SectionHeader(title: 'F&B Bills'),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          tokens.padding,
                          R.space(context, 8),
                          tokens.padding,
                          R.space(context, 8),
                        ),
                        child: _ScrollableCard(
                          child: _ExtrasList(
                            items: fnb,
                            currency: currency,
                            emptyText: 'No F&B items.',
                          ),
                        ),
                      ),
                    ),

                    // --- Miscellaneous Bills (scroll inside the section) ---
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: tokens.padding),
                      child: const _SectionHeader(title: 'Miscellaneous Bills'),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          tokens.padding,
                          R.space(context, 8),
                          tokens.padding,
                          R.space(context, 8),
                        ),
                        child: _ScrollableCard(
                          child: _ExtrasList(
                            items: misc,
                            currency: currency,
                            emptyText: 'No Miscellaneous items.',
                          ),
                        ),
                      ),
                    ),

                    SizedBox(
                        height: R.space(context, 80)), // keep clear of FABs
                  ],
                );
              },
            ),
          ),

          // --- Two side-by-side floating buttons ---
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: Padding(
            padding: EdgeInsets.symmetric(horizontal: R.space(context, 16)),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emGold,
                      foregroundColor: emGreen,
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveSize.of(context).h(14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radius),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      final added = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(
                          builder: (_) =>
                              BookingsAddBillPage(bookingId: widget.bookingId),
                        ),
                      );
                      if (added == true && mounted) {
                        setState(() => _future = _loadAll()); // refresh
                        // ignore: use_build_context_synchronously
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Bill added. Refreshed.')),
                        );
                      }
                    },
                    icon: Icon(Icons.add, size: R.icon(context, 18)),
                    label: const ResponsiveText(
                      'Add Bill',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
                SizedBox(width: R.space(context, 12)),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: emGold,
                      foregroundColor: emGreen,
                      padding: EdgeInsets.symmetric(
                        vertical: ResponsiveSize.of(context).h(14),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(tokens.radius),
                      ),
                      elevation: 2,
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BookingsFinaliseBillPage(
                            // remove `const`
                            bookingId: widget.bookingId, // pass the required id
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.check_circle, size: R.icon(context, 18)),
                    label: const ResponsiveText(
                      'Finalise Bill',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return null;
  }

  String _fmtMoney(dynamic v, String? currency) {
    if (v == null) return '—';
    final num? n = (v is num) ? v : num.tryParse('$v');
    if (n == null) return '—';
    final cur = (currency == null || currency.isEmpty) ? '' : '$currency ';
    return '$cur${n.toStringAsFixed(2)}';
  }

  num? _asNum(dynamic v) => (v is num) ? v : num.tryParse('${v ?? ''}');
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

// ---- UI atoms ----

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          top: R.space(context, 4), bottom: R.space(context, 6)),
      child: ResponsiveText(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: emGreen,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0x11000000)),
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      child: Padding(
        padding: EdgeInsets.all(tokens.padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ResponsiveText(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: emGreen,
              ),
            ),
            SizedBox(height: R.space(context, 10)),
            child,
          ],
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String label;
  final String value;
  const _BillRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: R.space(context, 6)),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: ResponsiveText(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: ResponsiveText(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollableCard extends StatelessWidget {
  final Widget child;
  const _ScrollableCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(tokens.radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.radius),
        child: child,
      ),
    );
  }
}

class _ExtrasList extends StatelessWidget {
  final List<_ExtraItem> items;
  final String? currency;
  final String emptyText;

  const _ExtrasList({
    required this.items,
    required this.currency,
    required this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(R.space(context, 16)),
          child: ResponsiveText(
            emptyText,
            style: const TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
      );
    }

    final df = DateFormat('d MMM yyyy • h:mm a');

    return ListView.separated(
      padding: EdgeInsets.symmetric(
        horizontal: R.space(context, 12),
        vertical: R.space(context, 8),
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) => SizedBox(height: R.space(context, 6)),
      itemBuilder: (context, i) {
        final e = items[i];
        final money = (currency == null || currency!.isEmpty)
            ? e.amount.toStringAsFixed(2)
            : '$currency ${e.amount.toStringAsFixed(2)}';

        return Padding(
          padding: EdgeInsets.symmetric(vertical: R.space(context, 4)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: ResponsiveText(
                  e.remarks?.isNotEmpty == true ? e.remarks! : '—',
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ResponsiveText(
                      money,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    ResponsiveText(
                      df.format(e.createdAt.toLocal()),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(R.space(context, 24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: R.icon(context, 36), color: Colors.redAccent),
            SizedBox(height: R.space(context, 12)),
            const ResponsiveText(
              'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(height: R.space(context, 16)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: emGold,
                foregroundColor: emGreen,
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
