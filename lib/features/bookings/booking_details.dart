import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'bookings_billings.dart';
//import 'bookings_advanced_search.dart';
//import 'bookings_finalise_bill.dart';
import 'dart:typed_data';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' as pdfd;
// Responsive system
import 'package:emville_pms/responsive/responsive.dart';
//import 'package:emville_pms/responsive/responsive_text.dart';
//import 'package:emville_pms/responsive/responsive_extensions.dart';
//import 'package:emville_pms/responsive/responsive_size.dart';

// Brand colors (explicit constants)
const emGreen = Color(0xFF103329);
const emGold = Color(0xFFD9A633);

// ---- Table / columns (exactly as you specified) ----
const kBookingsTable = 'booking_details';
const kIdCol = 'id';
const kStatusCol = 'status';
const kCheckInCol = 'check_in';
const kCheckOutCol = 'check_out';
const kGuestNameCol = 'guest_name';
const kNoOfPaxCol = 'no_of_pax';
const kSourceCol = 'source';
const kTotalPriceCol = 'total_price';
const kAdvancePaidCol = 'advance_paid';
const kBalanceCol = 'balance';
const kCurrencyCol = 'currency';
const kNotesCol = 'notes';

class BookingDetailsPage extends StatefulWidget {
  final String bookingId; // <-- pass the UUID from booking_details.id
  const BookingDetailsPage({super.key, required this.bookingId});

  @override
  State<BookingDetailsPage> createState() => _BookingDetailsPageState();
}

class _BookingDetailsPageState extends State<BookingDetailsPage> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = _fetchBooking();
  }

  Future<Map<String, dynamic>?> _fetchBooking() async {
    final fields = [
      kIdCol,
      kStatusCol,
      kCheckInCol,
      kCheckOutCol,
      kGuestNameCol,
      kNoOfPaxCol,
      kSourceCol,
      kTotalPriceCol,
      kAdvancePaidCol,
      kBalanceCol,
      kCurrencyCol,
      kNotesCol,
    ].join(', ');

    final resp = await Supabase.instance.client
        .from(kBookingsTable)
        .select(fields) // ⬅️ no type args
        .eq(kIdCol, widget.bookingId)
        .maybeSingle(); // Map<String, dynamic>? or null

    return resp;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: emGreen, // <-- force Emville green
        foregroundColor: Colors.white,
        title: const ResponsiveText(
          'Booking Details',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorState(
                error: snap.error,
                onRetry: () async => setState(() => _future = _fetchBooking()),
              );
            }
            final data = snap.data;
            if (data == null) {
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(R.space(context, 24)),
                  child: const ResponsiveText(
                    'Booking not found.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              );
            }

            // Read fields
            final guestName = _asStr(data[kGuestNameCol]);
            final status = _asStr(data[kStatusCol]);
            final checkIn = _parseDate(data[kCheckInCol]);
            final checkOut = _parseDate(data[kCheckOutCol]);
            final pax = _asInt(data[kNoOfPaxCol]);
            final source = _asStr(data[kSourceCol]);
            final total = _asNum(data[kTotalPriceCol]);
            final advance = _asNum(data[kAdvancePaidCol]);
            final balance = _asNum(data[kBalanceCol]);
            final currency = _asStr(data[kCurrencyCol]);
            final notes = _asStr(data[kNotesCol]);

            return ListView(
              padding: EdgeInsets.all(tokens.padding),
              children: [
                _SectionCard(
                  title: 'Guest & Status',
                  children: [
                    _Tile(k: 'Guest', v: guestName ?? '—', icon: Icons.person),
                    _Tile(
                        k: 'Status',
                        v: status ?? '—',
                        icon: Icons.info_outline),
                    _Tile(
                        k: 'Source',
                        v: source ?? '—',
                        icon: Icons.travel_explore),
                    _Tile(
                        k: 'No. of Pax',
                        v: pax?.toString() ?? '—',
                        icon: Icons.people_alt),
                  ],
                ),
                SizedBox(height: R.space(context, 12)),
                _SectionCard(
                  title: 'Stay',
                  children: [
                    _Tile(
                        k: 'Check-in', v: _fmtDate(checkIn), icon: Icons.login),
                    _Tile(
                        k: 'Check-out',
                        v: _fmtDate(checkOut),
                        icon: Icons.logout),
                  ],
                ),
                SizedBox(height: R.space(context, 12)),
                _SectionCard(
                  title: 'Billing Summary',
                  children: [
                    _Tile(
                        k: 'Currency',
                        v: currency ?? '—',
                        icon: Icons.currency_exchange),
                    _Tile(
                        k: 'Total Price',
                        v: _fmtMoney(total, currency),
                        icon: Icons.attach_money),
                    _Tile(
                        k: 'Advance Paid',
                        v: _fmtMoney(advance, currency),
                        icon: Icons.payments),
                    _Tile(
                        k: 'Balance',
                        v: _fmtMoney(balance, currency),
                        icon: Icons.account_balance_wallet),
                  ],
                ),
                SizedBox(height: R.space(context, 12)),
                _SectionCard(
                  title: 'Notes',
                  children: [
                    _Multiline(v: (notes?.isNotEmpty ?? false) ? notes! : '—'),
                  ],
                ),
                SizedBox(height: R.space(context, 24)),
                // Spacer so content isn't hidden behind bottom button
                SizedBox(height: R.space(context, 80)),
              ],
            );
          },
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        width: MediaQuery.of(context).size.width - R.space(context, 32),
        child: ElevatedButton.icon(
          onPressed: () async {
            final id = widget.bookingId; // current booking id

            // If already finalised, open the saved PDF
            if (await isFinalised(id)) {
              // ignore: use_build_context_synchronously
              final opened = await openSavedBillIfAny(context, id);
              if (!opened) {
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('No saved bill found for this booking.')),
                );
              }
              return;
            }

            // Not finalised yet → proceed to Billing page
            if (!mounted) return;
            // ignore: use_build_context_synchronously
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => BookingsBillingPage(bookingId: id),
              ),
            );
          },
          icon: Icon(Icons.receipt_long, size: R.icon(context, 20)),
          label: const ResponsiveText(
            'Billing',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ),
      ),
    );
  }

  // ---- Helpers ----

  DateTime? _parseDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) {
      try {
        return DateTime.parse(raw);
      } catch (_) {}
    }
    return null;
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    return DateFormat('EEE, d MMM yyyy • h:mm a').format(d.toLocal());
  }

  String _fmtMoney(num? v, String? currency) {
    if (v == null) return '—';
    final cur = (currency == null || currency.isEmpty) ? '' : '$currency ';
    // Keep it simple; you can plug intl NumberFormat later for locale-specific
    return '$cur${v.toStringAsFixed(2)}';
  }

  String? _asStr(dynamic v) => v?.toString();
  int? _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? ''}');
  num? _asNum(dynamic v) => (v is num) ? v : num.tryParse('${v ?? ''}');
}

// --- UI atoms (reusing your responsive system) ---

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

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
            const SizedBox(height: 2),
            ResponsiveText(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: emGreen,
              ),
            ),
            SizedBox(height: R.space(context, 10)),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final String k;
  final String v;
  final IconData? icon;
  const _Tile({required this.k, required this.v, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: R.space(context, 6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null)
            Padding(
              padding: EdgeInsets.only(
                  right: R.space(context, 8), top: R.space(context, 2)),
              child: Icon(icon, size: R.icon(context, 18), color: emGreen),
            ),
          Expanded(
            flex: 3,
            child: ResponsiveText(
              k,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          SizedBox(width: R.space(context, 8)),
          Expanded(
            flex: 7,
            child: ResponsiveText(
              v,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Multiline extends StatelessWidget {
  final String v;
  const _Multiline({required this.v});

  @override
  Widget build(BuildContext context) {
    return ResponsiveText(
      v,
      style: const TextStyle(
        fontSize: 14,
        color: Colors.black87,
      ),
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
            ResponsiveText(
              'Something went wrong.\n${error ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
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
// Put this in a shared place or top of the two files that need it.

// ---- Tables / buckets (reuse your constants if already defined) ----
//const kBookingsTable = 'booking_details';
const kBookingIdCol = 'id';
const kFinalisedCol = 'finalised';

const kGuestReceiptsTable = 'guest_receipts';
const kGRAttachmentPathCol = 'attachment_path';
const kReceiptsPdfBucket = 'guest_receipts_pdf';

// Returns true if booking_details.finalised is true
Future<bool> isFinalised(String bookingId) async {
  final supa = Supabase.instance.client;
  final row = await supa
      .from(kBookingsTable)
      .select(kFinalisedCol)
      .eq(kBookingIdCol, bookingId)
      .maybeSingle();
  return (row?[kFinalisedCol] == true);
}

// Opens the latest saved bill PDF if present; returns true if previewed
Future<bool> openSavedBillIfAny(BuildContext context, String bookingId) async {
  final supa = Supabase.instance.client;

  // Try to fetch the newest guest_receipts entry for this booking
  final rec = await supa
      .from(kGuestReceiptsTable)
      .select('$kGRAttachmentPathCol, created_at')
      .eq('booking_id', bookingId)
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

  final path = rec?[kGRAttachmentPathCol] as String?;
  if (path == null || path.isEmpty) return false;

  // Download the pdf bytes from storage and preview
  final bytes = await supa.storage.from(kReceiptsPdfBucket).download(path);

  if (!context.mounted) return true;
  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BillPdfPreviewPage(
        title: 'Final Bill',
        pdfBytes: bytes,
      ),
    ),
  );
  return true;
}

class BillPdfPreviewPage extends StatelessWidget {
  final String title;
  final Uint8List pdfBytes;
  const BillPdfPreviewPage(
      {super.key, required this.title, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF103329), // emGreen
        foregroundColor: Colors.white,
        title: ResponsiveText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        canChangeOrientation: false,
        canChangePageFormat: false,
        allowPrinting: true,
        allowSharing: true,
        initialPageFormat: pdfd.PdfPageFormat.a4,
      ),
    );
  }
}
