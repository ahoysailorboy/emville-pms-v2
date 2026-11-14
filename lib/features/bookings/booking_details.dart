import 'booking_style.dart';
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

  Future<void> _openBilling() async {
    try {
      final id = widget.bookingId;
      if (await isFinalised(id)) {
        if (!mounted) return;
        final opened = await openSavedBillIfAny(context, id);
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No saved bill found for this booking.')));
        }
        return;
      }
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookingsBillingPage(bookingId: id)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to open billing. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final checkIn = bookingDate(data?[kCheckInCol]);
        final checkOut = bookingDate(data?[kCheckOutCol]);
        final nights = checkIn == null || checkOut == null
            ? null
            : DateTime(checkOut.year, checkOut.month, checkOut.day)
                .difference(DateTime(checkIn.year, checkIn.month, checkIn.day))
                .inDays;
        final currency = _asStr(data?[kCurrencyCol]) ?? 'INR';
        Widget stayDate(String label, DateTime? date) => Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(label.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.4,
                          color: Emville.muted)),
                  const SizedBox(height: 8),
                  Text(
                      date == null
                          ? '—'
                          : DateFormat('d MMM yyyy').format(date),
                      style: Emville.heading(19)),
                  const SizedBox(height: 5),
                  Text(
                      date == null
                          ? '—'
                          : DateFormat('EEEE · h:mm a').format(date),
                      style:
                          const TextStyle(fontSize: 10, color: Emville.muted))
                ]));
        return BookingFrame(
            title: 'Booking details',
            subtitle: 'A thoughtful stay, with every detail in place.',
            actions: data == null
                ? null
                : FilledButton.icon(
                    onPressed: _openBilling,
                    icon: const Icon(Icons.receipt_long_outlined, size: 17),
                    label: const Text('View billing')),
            children: [
              if (snapshot.hasError)
                EmvilleError(onRetry: () async {
                  setState(() {
                    _future = _fetchBooking();
                  });
                })
              else if (snapshot.connectionState == ConnectionState.waiting)
                const Center(child: CircularProgressIndicator())
              else if (data == null)
                const Center(child: Text('Booking not found.'))
              else ...[
                BookingCard(children: [
                  Row(children: [
                    const Expanded(
                        child: Text('GUEST & STATUS',
                            style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.4,
                                color: Emville.muted))),
                    Flexible(
                        child: Align(
                            alignment: Alignment.centerRight,
                            child: EmvilleTag(
                                _asStr(data[kStatusCol]) ?? 'Unknown',
                                warning: data[kStatusCol] != 'confirmed')))
                  ]),
                  const SizedBox(height: 14),
                  Text(_asStr(data[kGuestNameCol]) ?? 'Guest',
                      style: Emville.heading(26)),
                  const SizedBox(height: 14),
                  Wrap(spacing: 20, runSpacing: 10, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.people_alt_outlined, size: 16),
                      const SizedBox(width: 7),
                      Text('${_asInt(data[kNoOfPaxCol]) ?? '—'} guests',
                          style: const TextStyle(fontSize: 11))
                    ]),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.travel_explore, size: 16),
                      const SizedBox(width: 7),
                      Text(_asStr(data[kSourceCol]) ?? '—',
                          style: const TextStyle(fontSize: 11))
                    ])
                  ])
                ]),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: Text('The stay', style: Emville.heading(22))),
                  if (nights != null && nights >= 0)
                    EmvilleTag('$nights ${nights == 1 ? 'night' : 'nights'}')
                ]),
                const SizedBox(height: 13),
                BookingCard(children: [
                  Row(children: [
                    stayDate('Check-in', checkIn),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(Icons.arrow_forward,
                            size: 17, color: Emville.muted)),
                    stayDate('Check-out', checkOut)
                  ])
                ]),
                bookingSection('Payment summary'),
                BookingCard(children: [
                  BookingValue('Currency', currency),
                  BookingValue('Total price',
                      bookingMoney(data[kTotalPriceCol], currency)),
                  BookingValue('Advance paid',
                      bookingMoney(data[kAdvancePaidCol], currency)),
                  const Padding(
                      padding: EdgeInsets.symmetric(vertical: 7),
                      child: Divider(height: 1)),
                  BookingValue('Balance to be paid',
                      bookingMoney(data[kBalanceCol], currency),
                      strong: true)
                ]),
                bookingSection('Notes'),
                BookingCard(children: [
                  Text(
                      _asStr(data[kNotesCol])?.trim().isNotEmpty == true
                          ? data[kNotesCol].toString()
                          : 'No notes added.',
                      style: const TextStyle(
                          fontSize: 11, color: Emville.muted, height: 1.5))
                ]),
              ]
            ]);
      });

  // ---- Helpers ----

  String? _asStr(dynamic v) => v?.toString();
  int? _asInt(dynamic v) => (v is num) ? v.toInt() : int.tryParse('${v ?? ''}');
}

const kBookingIdCol = 'id';
const kFinalisedCol = 'finalised';
const kGuestReceiptsTable = 'guest_receipts';
const kGRAttachmentPathCol = 'attachment_path';
const kReceiptsPdfBucket = 'guest_receipts_pdf';

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
