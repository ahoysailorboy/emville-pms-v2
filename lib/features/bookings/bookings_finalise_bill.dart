import 'booking_style.dart';
import 'package:emville_pms/ui/emville_pdf_letterhead.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart' as pdfd;
import 'bookings_billings.dart'; // for navigation back to billing if edit
//import 'booking_details.dart';
// Responsive system
import 'package:emville_pms/responsive/responsive_theme.dart';
import 'package:emville_pms/responsive/responsive_text.dart';
import 'package:emville_pms/responsive/responsive_size.dart';

// Brand colors
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
const kCheckOutCol = 'check_out';
const kBalanceCol = 'balance';
const kCurrencyCol = 'currency';
const kFinalisedCol = 'finalised';

const kExtrasTable = 'bookings_extras';
const kExtrasBookingIdCol = 'booking_id';
const kExtrasTypeCol = 'bill_type'; // 'f&b' | 'other'
const kExtrasAmountCol = 'amount';
const kExtrasRemarksCol = 'remarks';
const kExtrasBillDateCol = 'bill_date'; // optional, if present
const kExtrasCreatedCol = 'created_at';

// ---- Storage buckets ----
const kReceiptsBucket = 'receipts'; // photo proof bucket
const kReceiptsPdfBucket = 'guest_receipts_pdf'; // pdf bill bucket

// ---- guest_receipts table ----
const kGuestReceiptsTable = 'guest_receipts';
const kGRGuestNameCol = 'guest_name';
const kGRBookingIdCol = 'booking_id';
const kGRCheckInCol = 'check_in';
const kGRCheckOutCol = 'check_out';
const kGRCreatedByCol = 'created_by';
const kGRAttachmentPathCol = 'attachment_path';

// ---- main_ledger table ----
const kMainLedgerTable = 'main_ledger';
const kMLDateCol = 'date';
const kMLAmountCol = 'amount';
const kMLTypeCol = 'transaction_type'; // 'income'
const kMLPayeeCol = 'payee_payer_name';
const kMLRemarksCol = 'remarks';
const kMLStatusCol = 'transaction_status'; // 'pending'
const kMLCreatedByCol = 'created_by'; // optional (text/name or id string)
const kMLApprovedByCol = 'approved_by';
const kMLAttachmentPathCol = 'attachment_path';
const kMLPaymentModeCol = 'payment_mode'; // Bank Transfer / Cash / Card / UPI
const kMLCreatorUuidCol = 'creator_uuid'; // REQUIRED (uuid, non-null)

// ============ PAGE ============

class BookingsFinaliseBillPage extends StatefulWidget {
  final String bookingId;
  const BookingsFinaliseBillPage({super.key, required this.bookingId});

  @override
  State<BookingsFinaliseBillPage> createState() =>
      _BookingsFinaliseBillPageState();
}

class _BookingsFinaliseBillPageState extends State<BookingsFinaliseBillPage> {
  late Future<_BillContext> _future;
  _FinaliseInput? _input; // set after dialog OK
  Uint8List? _proofImageBytes;
  String? _proofImageExt; // jpg/png
  bool _dialogShown = false; // ensure we auto-open only once
  bool? _isFinalised;

  @override
  void initState() {
    super.initState();
    _future = _loadContext();
    _checkFinalised();
  }

  Future<void> _checkFinalised() async {
    final ok = await isFinalised(widget.bookingId);
    if (mounted) setState(() => _isFinalised = ok);
  }

  Future<_BillContext> _loadContext() async {
    final supa = Supabase.instance.client;

    // Booking header
    final booking = await supa
        .from(kBookingsTable)
        .select(
            '$kBookingIdCol, $kGuestNameCol, $kTotalPriceCol, $kAdvancePaidCol, '
            '$kSourceCol, $kCheckInCol, $kCheckOutCol, $kBalanceCol, $kCurrencyCol')
        .eq(kBookingIdCol, widget.bookingId)
        .maybeSingle();

    if (booking == null) throw StateError('Booking not found.');

    // F&B
    final fnbRaw = await supa
        .from(kExtrasTable)
        .select(
            '$kExtrasAmountCol, $kExtrasRemarksCol, $kExtrasCreatedCol, $kExtrasBillDateCol')
        .eq(kExtrasBookingIdCol, widget.bookingId)
        .eq(kExtrasTypeCol, 'f&b')
        .order(kExtrasCreatedCol, ascending: true);

    // Others
    final miscRaw = await supa
        .from(kExtrasTable)
        .select(
            '$kExtrasAmountCol, $kExtrasRemarksCol, $kExtrasCreatedCol, $kExtrasBillDateCol')
        .eq(kExtrasBookingIdCol, widget.bookingId)
        .eq(kExtrasTypeCol, 'other')
        .order(kExtrasCreatedCol, ascending: true);

    final fnb = (fnbRaw as List)
        .map((e) => _ExtraItem.fromJson(e as Map<String, dynamic>))
        .toList();
    final misc = (miscRaw as List)
        .map((e) => _ExtraItem.fromJson(e as Map<String, dynamic>))
        .toList();

    return _BillContext(booking: booking, fnb: fnb, misc: misc);
  }

  Future<void> _openFinaliseDialog(_BillContext ctx) async {
    if (_isFinalised == true) {
      _showSnack('Already finalised. Open the saved bill from details.',
          isError: true);
      return;
    }
    final now = DateTime.now();
    final result = await showDialog<_FinaliseInput>(
      context: context,
      builder: (_) => _DiscountsPaymentDialog(
        guestName: ctx.guestName ?? '',
        checkIn: ctx.checkIn,
        initialCheckOut: now,
        currency: ctx.currency ?? 'INR',
        fnbTotal: ctx.fnbTotal,
        otherTotal: ctx.otherTotal,
      ),
    );
    if (!mounted) return;
    if (result == null) {
      // user canceled: just pop back to billing page
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _input = result);
  }

  Future<void> _pickProofImage() async {
    final picker = ImagePicker();
    final file = await showDialog<XFile?>(
      context: context,
      builder: (_) => _ProofPickerDialog(picker: picker),
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _proofImageBytes = bytes;
        _proofImageExt =
            p.extension(file.path).toLowerCase().replaceAll('.', '');
        if (_proofImageExt!.isEmpty) _proofImageExt = 'jpg';
      });
    }
  }

  Future<void> _confirmAndSave(_BillContext ctx) async {
    if (_input == null) {
      _showSnack('Please fill discounts & payment first.', isError: true);
      return;
    }
    if (!_input!.isPaymentSectionValid) {
      _showSnack('Payment section cannot be blank.', isError: true);
      return;
    }
    if (_isFinalised == true) {
      _showSnack('Already finalised. Open the saved bill from details.',
          isError: true);
      return;
    }

    try {
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) {
        _showSnack('You must be logged in to finalise a bill', isError: true);
        return;
      }

      // 1) Upload proof only if provided (optional attachment)
      String? proofPath;
      if (_proofImageBytes != null) {
        proofPath = await _ReceiptStorageService.uploadProofImage(
          supa: supa,
          bytes: _proofImageBytes!,
          ext: _proofImageExt ?? 'jpg',
          bookingId: widget.bookingId,
        );
      }

      // 2) Insert into main_ledger
      final amountDue = _BillMath(ctx, _input!).amountDueAfterDiscounts;
      await _LedgerService.insert(
        supa: supa,
        date: _input!.paymentDate,
        amount: amountDue,
        guestName: ctx.guestName ?? 'Guest',
        remarks: 'Stay from ${_d(ctx.checkIn)} to ${_d(_input!.checkOutDate)}',
        createdBy: user.id, // ok if nullable in DB
        creatorUuid: user.id, // REQUIRED in your schema
        paymentMode: _input!.paymentType,
        proofPath: proofPath, // nullable
      );

      // 3) Generate PDF bill bytes
      final pdfBytes = await _PdfService.generateBillPdf(
        ctx: ctx,
        input: _input!,
      );

      // 4) Upload PDF + insert guest_receipts row
      await _PdfService.uploadPdfAndInsertRow(
        supa: supa,
        pdfBytes: pdfBytes,
        bookingId: widget.bookingId,
        guestName: ctx.guestName ?? 'Guest',
        checkIn: ctx.checkIn,
        checkOut: _input!.checkOutDate,
        createdBy: user.id,
      );

      // 5) Mark booking as finalised (safeguard)
      await supa
          .from(kBookingsTable)
          .update({'finalised': true}).eq(kBookingIdCol, widget.bookingId);

      // 6) Show preview immediately so the user can print/share
      if (!mounted) return;
      _showSnack('Final bill saved. PDF uploaded.', isError: false);

      final title =
          '${ctx.guestName ?? 'Guest'} • ${DateFormat('d MMM yyyy').format(_input!.checkOutDate)}';

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _BillPdfPreviewPage(
            title: title,
            pdfBytes: pdfBytes,
          ),
        ),
      );

      // 7) After closing preview, pop back to previous screen (e.g., billings)
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack('Failed to finalise: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_BillContext>(
      future: _future,
      builder: (context, snapshot) {
        final ctx = snapshot.data;
        if (ctx != null && !_dialogShown && _input == null) {
          _dialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openFinaliseDialog(ctx);
          });
        }
        if (_input != null && ctx != null) {
          return EmvillePage(
              section: 1,
              child: EmvilleBody(
                  child: Column(children: [
                Padding(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 0),
                    child: EmvilleHeading('Review final bill',
                        eyebrow: 'Bookings / Billing',
                        subtitle: ctx.guestName ?? 'Guest')),
                Expanded(
                    child: _BillPreviewSheet(
                        ctx: ctx,
                        input: _input!,
                        math: _BillMath(ctx, _input!),
                        onEdit: () {
                          Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                  builder: (_) => BookingsBillingPage(
                                      bookingId: widget.bookingId)));
                        },
                        onAttachProof: _pickProofImage,
                        proofPicked: _proofImageBytes != null,
                        onConfirm: () => _confirmAndSave(ctx)))
              ])));
        }
        return BookingFrame(
            title: 'Billing',
            subtitle: ctx?.guestName ?? 'Review this stay before finalising.',
            children: [
              if (snapshot.hasError)
                EmvilleError(onRetry: () async {
                  setState(() {
                    _future = _loadContext();
                  });
                })
              else if (ctx == null)
                const Center(child: CircularProgressIndicator())
              else
                BookingBalance(
                    amount: ctx.balance + ctx.fnbTotal + ctx.otherTotal,
                    currency: ctx.currency ?? 'INR',
                    detail:
                        'Room rent ${_m(ctx.roomTotal, ctx.currency)} · Advance paid ${_m(ctx.advancePaid, ctx.currency)}')
            ]);
      });

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ResponsiveText(msg, style: const TextStyle(fontSize: 14)),
        backgroundColor: isError ? Colors.redAccent : emGreen,
      ),
    );
  }
}

// ============ MODELS & SERVICES ============

class _BillContext {
  final Map<String, dynamic>? booking;
  final List<_ExtraItem> fnb;
  final List<_ExtraItem> misc;

  _BillContext({required this.booking, required this.fnb, required this.misc});

  String? get guestName => booking?[kGuestNameCol] as String?;
  DateTime? get checkIn => _parseDate(booking?[kCheckInCol]);
  DateTime? get checkOut => _parseDate(booking?[kCheckOutCol]);
  num get balance => _asNum(booking?[kBalanceCol]);
  num get roomTotal => _asNum(booking?[kTotalPriceCol]);
  num get advancePaid => _asNum(booking?[kAdvancePaidCol]);
  String? get currency => booking?[kCurrencyCol] as String?;

  num get fnbTotal => fnb.fold<num>(0, (s, e) => s + e.amount);
  num get otherTotal => misc.fold<num>(0, (s, e) => s + e.amount);
}

class _FinaliseInput {
  // Discounts (%)
  final double fnbDiscountPct; // 0-100
  final double otherDiscountPct; // 0-100

  // Payment section
  final DateTime checkInDate; // from booking but editable
  final DateTime checkOutDate; // default now, <= today
  final DateTime paymentDate; // default now, <= today
  final String payeeName;
  final String paymentType; // Bank Transfer / Cash / Card / UPI

  _FinaliseInput({
    required this.fnbDiscountPct,
    required this.otherDiscountPct,
    required this.checkInDate,
    required this.checkOutDate,
    required this.paymentDate,
    required this.payeeName,
    required this.paymentType,
  });

  bool get isPaymentSectionValid =>
      payeeName.trim().isNotEmpty &&
      (paymentType == 'Bank Transfer' ||
          paymentType == 'Cash' ||
          paymentType == 'Card' ||
          paymentType == 'UPI');
}

class _BillMath {
  final _BillContext ctx;
  final _FinaliseInput input;

  _BillMath(this.ctx, this.input);

  num get fnbAfterDiscount {
    final d = (input.fnbDiscountPct.clamp(0, 100)) / 100.0;
    final val = ctx.fnbTotal * (1 - d);
    return _round2(val);
  }

  num get otherAfterDiscount {
    final d = (input.otherDiscountPct.clamp(0, 100)) / 100.0;
    final val = ctx.otherTotal * (1 - d);
    return _round2(val);
  }

  /// Spec: Balance due after discounts:
  /// booking.balance + discounted(F&B + Others)
  num get amountDueAfterDiscounts {
    final val = ctx.balance + fnbAfterDiscount + otherAfterDiscount;
    return _round2(val);
  }

  num get grandTotalBeforeAdvance {
    // Rendered bill sections (Accommodation + F&B + Others) total
    return _round2(ctx.roomTotal + ctx.fnbTotal + ctx.otherTotal);
  }

  static num _round2(num v) => num.parse(v.toStringAsFixed(2));
}

class _LedgerService {
  static Future<void> insert({
    required SupabaseClient supa,
    required DateTime date,
    required num amount,
    required String guestName,
    required String remarks,
    required String? createdBy, // can be null
    required String paymentMode,
    required String creatorUuid, // current user id (uuid)
    String? proofPath, // <-- made nullable
  }) async {
    await supa.from(kMainLedgerTable).insert({
      kMLDateCol: date.toIso8601String(),
      kMLAmountCol: amount,
      kMLTypeCol: 'income',
      kMLPayeeCol: guestName,
      kMLRemarksCol: remarks,
      kMLStatusCol: 'pending',
      kMLCreatedByCol: createdBy, // nullable ok if column allows null
      kMLApprovedByCol: null,
      kMLAttachmentPathCol: proofPath, // <-- write nullable
      kMLPaymentModeCol: paymentMode,
      kMLCreatorUuidCol: creatorUuid, // <-- don’t forget to persist this
    });
  }
}

class _ReceiptStorageService {
  /// Uploads proof image to `receipts/booking_<id>/<timestamp>.<ext>`
  static Future<String> uploadProofImage({
    required SupabaseClient supa,
    required Uint8List bytes,
    required String ext,
    required String bookingId,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final path = 'booking_$bookingId/$ts.$ext';
    await supa.storage.from(kReceiptsBucket).uploadBinary(path, bytes);
    return path; // stored path
  }
}

class _PdfService {
  static Future<Uint8List> generateBillPdf({
    required _BillContext ctx,
    required _FinaliseInput input,
  }) async {
    // --- Assets (guarded) ---
    final logoBytes = await rootBundle.load('assets/brand/emville-logo.png');
    final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // --- Fonts (Roboto Regular & Italic) ---
    final roboto = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final robotoItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );

    // --- Themed document ---
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: roboto,
        bold: roboto, // add Roboto-Bold.ttf later if you want real bold
        italic: robotoItalic,
      ),
    );

    // --- Colors & spacing ---
    final pdfGreen = pdfd.PdfColor.fromInt(emGreen.toARGB32());
    final pdfGold = pdfd.PdfColor.fromInt(emGold.toARGB32());
    // ignore: unused_local_variable
    const hSmall = 8.0, h = 12.0, hLarge = 18.0;

    // --- Formatters & helpers ---
    final df = DateFormat('dd-MM-yyyy');
    String fmt(DateTime? d) => d == null ? '—' : df.format(d.toLocal());
    String money(num v, String? c) => (c == null || c.isEmpty)
        ? v.toStringAsFixed(2)
        : '$c ${v.toStringAsFixed(2)}';

    // Key–value row used in booking details section
    pw.Widget kv(String k, String v) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(k,
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ),
            pw.SizedBox(width: 12),
            pw.Text(v, style: const pw.TextStyle(fontSize: 12)),
          ],
        );

    // Table header (Date | Particulars | Amount)
    pw.Widget tableHeader() => pw.Container(
          color: pdfGreen,
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          child: pw.Row(
            children: [
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Date',
                  style: pw.TextStyle(
                    color: pdfGold,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              pw.Expanded(
                flex: 6,
                child: pw.Text(
                  'Particulars',
                  style: pw.TextStyle(
                    color: pdfGold,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              pw.Expanded(
                flex: 2,
                child: pw.Text(
                  'Amount',
                  textAlign: pw.TextAlign.right,
                  style: pw.TextStyle(
                    color: pdfGold,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );

    // Section label (bold) shown just under the header
    pw.Widget sectionRow(String title) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: pdfGreen,
            ),
          ),
        );

    // Generic table rows renderer: each row is [date, particulars, amount]
    pw.Widget tableRows(List<List<String>> rows) => pw.Column(
          children: rows
              .map(
                (r) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                      vertical: 6, horizontal: 10),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(r.elementAt(0),
                            style: const pw.TextStyle(fontSize: 11)),
                      ),
                      pw.Expanded(
                        flex: 6,
                        child: pw.Text(r.elementAt(1),
                            style: const pw.TextStyle(fontSize: 11)),
                      ),
                      pw.Expanded(
                        flex: 2,
                        child: pw.Text(
                          r.elementAt(2),
                          textAlign: pw.TextAlign.right,
                          style: const pw.TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );

    // --- Build rows (safe, no `!`) ---
    // Accommodation: date shown = check-in (change to fmt(input.checkOutDate) if preferred)
    final accommodationRows = <List<String>>[
      [fmt(ctx.checkIn), 'Room Rent', money(ctx.roomTotal, ctx.currency)],
    ];

    // F&B rows: prefer billDate, else createdAt (both safely handled)
    final fnbRows = ctx.fnb.map((e) {
      final when = e.billDate ?? e.createdAt;
      final label =
          (e.remarks?.trim().isNotEmpty == true) ? e.remarks!.trim() : '-';
      return [fmt(when), label, money(e.amount, ctx.currency)];
    }).toList(growable: false);

    // Other rows: prefer billDate, else createdAt
    final otherRows = ctx.misc.map((e) {
      final when = e.billDate ?? e.createdAt;
      final label =
          (e.remarks?.trim().isNotEmpty == true) ? e.remarks!.trim() : '-';
      return [fmt(when), label, money(e.amount, ctx.currency)];
    }).toList(growable: false);

    // --- Assemble PDF ---
    doc.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            emvillePdfLetterhead(logoImage),
            pw.SizedBox(height: hLarge),

            // Booking details
            kv('Guest Name', ctx.guestName ?? '—'),
            pw.SizedBox(height: hSmall),
            kv('Check In Date', fmt(ctx.checkIn)),
            pw.SizedBox(height: hSmall),
            kv('Check Out Date', fmt(input.checkOutDate)),
            pw.SizedBox(height: hLarge),

            // Table header once, then sections
            tableHeader(),

            // Accommodation
            sectionRow('Accommodation'),
            tableRows(accommodationRows),
            pw.SizedBox(height: hSmall),

            // F&B
            sectionRow('F&B'),
            fnbRows.isEmpty
                ? pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 10, horizontal: 10),
                    child: pw.Text('No F&B items',
                        style: const pw.TextStyle(fontSize: 11)),
                  )
                : tableRows(fnbRows),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, right: 10),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Discount (${input.fnbDiscountPct.toStringAsFixed(0)}%)   '
                  '${money(_BillMath(ctx, input).fnbAfterDiscount, ctx.currency)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ),
            pw.SizedBox(height: hSmall),

            // Other
            sectionRow('Other'),
            otherRows.isEmpty
                ? pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 10, horizontal: 10),
                    child: pw.Text('No Other items',
                        style: const pw.TextStyle(fontSize: 11)),
                  )
                : tableRows(otherRows),
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4, right: 10),
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  'Discount (${input.otherDiscountPct.toStringAsFixed(0)}%)   '
                  '${money(_BillMath(ctx, input).otherAfterDiscount, ctx.currency)}',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ),
            pw.SizedBox(height: hLarge),

            // Totals
            pw.Divider(),
            pw.Row(
              children: [
                pw.Spacer(),
                pw.Text('Advance Paid: ',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(money(ctx.advancePaid, ctx.currency),
                    style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Spacer(),
                pw.Text('Total to Pay: ',
                    style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: pdfGreen)),
                pw.Text(
                  money(_BillMath(ctx, input).amountDueAfterDiscounts,
                      ctx.currency),
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: pdfGreen),
                ),
              ],
            ),
            pw.Divider(),
            pw.SizedBox(height: hLarge),

            // Signature / manager block
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.SizedBox(height: 36), // space for seal
                  pw.Text('Manager',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('Emville Hospitality, Chelamattom',
                      style: const pw.TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static Future<String> uploadPdfAndInsertRow({
    required SupabaseClient supa,
    required Uint8List pdfBytes,
    required String bookingId,
    required String guestName,
    required DateTime? checkIn,
    required DateTime checkOut,
    required String? createdBy,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final pdfPath = 'booking_$bookingId/$ts.pdf';
    await supa.storage.from(kReceiptsPdfBucket).uploadBinary(pdfPath, pdfBytes);

    await supa.from(kGuestReceiptsTable).insert({
      kGRGuestNameCol: guestName,
      kGRBookingIdCol: bookingId,
      kGRCheckInCol: _dateOnlyStr(checkIn), // 'YYYY-MM-DD' or null
      kGRCheckOutCol: _dateOnlyStr(checkOut), // 'YYYY-MM-DD'
      kGRCreatedByCol: createdBy,
      kGRAttachmentPathCol: pdfPath,
    });

    return pdfPath;
  }

  static String? _dateOnlyStr(DateTime? d) {
    if (d == null) return null;
    return DateFormat('yyyy-MM-dd').format(d.toLocal());
  }
}

// ============ UI DIALOG & PREVIEW ============

class _DiscountsPaymentDialog extends StatefulWidget {
  final String guestName;
  final DateTime? checkIn;
  final DateTime initialCheckOut;
  final String? currency;
  final num fnbTotal;
  final num otherTotal;

  const _DiscountsPaymentDialog({
    required this.guestName,
    required this.checkIn,
    required this.initialCheckOut,
    required this.currency,
    required this.fnbTotal,
    required this.otherTotal,
  });

  @override
  State<_DiscountsPaymentDialog> createState() =>
      _DiscountsPaymentDialogState();
}

class _DiscountsPaymentDialogState extends State<_DiscountsPaymentDialog> {
  final _form = GlobalKey<FormState>();

  double _fnbDisc = 0;
  double _otherDisc = 0;

  late DateTime _checkIn;
  late DateTime _checkOut;
  late DateTime _paymentDate;

  final _payeeCtrl = TextEditingController();
  String _paymentType = 'Cash'; // default

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkIn = widget.checkIn ?? DateTime(now.year, now.month, now.day);
    _checkOut = DateTime(now.year, now.month, now.day);
    _paymentDate = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _payeeCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCheckIn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkIn.isAfter(DateTime.now()) ? DateTime.now() : _checkIn,
      firstDate: DateTime(_checkIn.year - 5),
      lastDate: DateTime.now(), // cannot be future
    );
    if (picked != null) setState(() => _checkIn = picked);
  }

  Future<void> _pickCheckOut() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkOut,
      firstDate: DateTime(_checkIn.year - 5),
      lastDate: DateTime.now(), // cannot be future
    );
    if (picked != null) setState(() => _checkOut = picked);
  }

  Future<void> _pickPaymentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(_paymentDate.year - 5),
      lastDate: DateTime.now(), // cannot be future
    );
    if (picked != null) setState(() => _paymentDate = picked);
  }

  void _continue() {
    if (_form.currentState?.validate() != true) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_checkOut.isAfter(today) || _paymentDate.isAfter(today)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dates cannot be in the future.')));
      return;
    }
    if (DateTime(_checkOut.year, _checkOut.month, _checkOut.day)
        .isBefore(DateTime(_checkIn.year, _checkIn.month, _checkIn.day))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Check-out cannot be before check-in.')));
      return;
    }
    Navigator.pop(
        context,
        _FinaliseInput(
            fnbDiscountPct: _fnbDisc,
            otherDiscountPct: _otherDisc,
            checkInDate: _checkIn,
            checkOutDate: _checkOut,
            paymentDate: _paymentDate,
            payeeName: _payeeCtrl.text.trim(),
            paymentType: _paymentType));
  }

  @override
  Widget build(BuildContext context) {
    final fnbAfter = widget.fnbTotal * (1 - (_fnbDisc.clamp(0, 100) / 100));
    final otherAfter =
        widget.otherTotal * (1 - (_otherDisc.clamp(0, 100) / 100));
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      backgroundColor: Emville.ivory,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Flexible(
                    child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 22, 22, 12),
                        child: Form(
                            key: _form,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Text('Finalise bill',
                                            style: Emville.heading(28))),
                                    IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => Navigator.pop(context),
                                        tooltip: 'Close',
                                        icon: const Icon(Icons.close, size: 18))
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${widget.guestName} · Review payment details',
                                      style: const TextStyle(
                                          fontSize: 10, color: Emville.muted)),
                                  const SizedBox(height: 22),
                                  Text('Discounts', style: Emville.heading(21)),
                                  const SizedBox(height: 12),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                            child: _percentField(
                                                'F&B (%)',
                                                _fnbDisc,
                                                (v) => setState(
                                                    () => _fnbDisc = v))),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: _percentField(
                                                'Other (%)',
                                                _otherDisc,
                                                (v) => setState(
                                                    () => _otherDisc = v)))
                                      ]),
                                  const SizedBox(height: 13),
                                  Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                          color: Emville.sage,
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      child: Wrap(
                                          alignment: WrapAlignment.spaceBetween,
                                          spacing: 10,
                                          runSpacing: 5,
                                          children: [
                                            const Text('After discounts',
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    color: Emville.muted)),
                                            Text(
                                                'F&B ${bookingMoney(fnbAfter, widget.currency)} · Other ${bookingMoney(otherAfter, widget.currency)}',
                                                style: const TextStyle(
                                                    fontSize: 10))
                                          ])),
                                  const SizedBox(height: 22),
                                  Text('Payment', style: Emville.heading(21)),
                                  const SizedBox(height: 13),
                                  _dateRow(
                                      'Check-in date', _checkIn, _pickCheckIn),
                                  _dateRow('Check-out date', _checkOut,
                                      _pickCheckOut),
                                  _dateRow('Payment date', _paymentDate,
                                      _pickPaymentDate),
                                  bookingLabel('Payee name'),
                                  TextFormField(
                                      key: const ValueKey('finalise-payee'),
                                      controller: _payeeCtrl,
                                      style: const TextStyle(fontSize: 12),
                                      decoration: bookingDecoration(
                                          hint: 'Enter payee name'),
                                      validator: (v) =>
                                          v?.trim().isNotEmpty == true
                                              ? null
                                              : 'Required'),
                                  const SizedBox(height: 12),
                                  bookingLabel('Payment type'),
                                  DropdownButtonFormField<String>(
                                      key: const ValueKey(
                                          'finalise-payment-type'),
                                      initialValue: _paymentType,
                                      isExpanded: true,
                                      style: const TextStyle(
                                          fontFamily: 'Roboto',
                                          fontSize: 12,
                                          color: Emville.ink),
                                      decoration: bookingDecoration(),
                                      items: [
                                        for (final mode in [
                                          'Cash',
                                          'UPI',
                                          'Card',
                                          'Bank Transfer'
                                        ])
                                          DropdownMenuItem(
                                              value: mode, child: Text(mode))
                                      ],
                                      onChanged: (v) => setState(
                                          () => _paymentType = v ?? 'Cash')),
                                  const SizedBox(height: 19),
                                  const Text(
                                      'Continue to review the final bill before saving.',
                                      style: TextStyle(
                                          fontSize: 10,
                                          height: 1.5,
                                          color: Emville.muted)),
                                ])))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                    child: Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FilledButton(
                              onPressed: _continue,
                              child: const Text('Continue')))
                    ])),
              ])),
    );
  }

  Widget _percentField(
          String label, double value, ValueChanged<double> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bookingLabel(label),
        TextFormField(
            key: ValueKey(label),
            initialValue: value.toStringAsFixed(0),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 12),
            decoration: bookingDecoration(hint: '0–100'),
            validator: (s) {
              final n = double.tryParse(s ?? '');
              return n == null || !n.isFinite || n < 0 || n > 100
                  ? 'Use 0–100'
                  : null;
            },
            onChanged: (s) {
              final n = double.tryParse(s);
              if (n != null && n.isFinite) onChanged(n.clamp(0, 100));
            })
      ]);
  Widget _dateRow(String label, DateTime value, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bookingLabel(label),
        InkWell(
            onTap: onTap,
            child: InputDecorator(
                decoration: bookingDecoration(),
                child: Row(children: [
                  Expanded(
                      child: Text(DateFormat('d MMM yyyy').format(value),
                          style: const TextStyle(fontSize: 12))),
                  const Icon(Icons.calendar_today_outlined, size: 16)
                ])))
      ]));
}

class _BillPreviewSheet extends StatelessWidget {
  final _BillContext ctx;
  final _FinaliseInput input;
  final _BillMath math;
  final VoidCallback onEdit;
  final VoidCallback onAttachProof;
  final bool proofPicked;
  final VoidCallback onConfirm;

  const _BillPreviewSheet({
    required this.ctx,
    required this.input,
    required this.math,
    required this.onEdit,
    required this.onAttachProof,
    required this.proofPicked,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(R.tokens(context).padding),
      children: [
        // Accommodation
        _SectionCard(
          title: 'Accommodation',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KeyVal('Room Rent', _m(ctx.roomTotal, ctx.currency)),
              _KeyVal('Check-In', _d(ctx.checkIn)),
              _KeyVal('Check-Out', _d(input.checkOutDate)),
            ],
          ),
        ),
        SizedBox(height: R.space(context, 12)),

        // F&B
        _SectionCard(
          title: 'F&B',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...ctx.fnb.map(
                  (e) => _KeyVal(e.remarks ?? '-', _m(e.amount, ctx.currency))),
              _KeyVal('F&B Discount',
                  '${input.fnbDiscountPct.toStringAsFixed(0)}%'),
              _KeyVal('F&B After Discount',
                  _m(math.fnbAfterDiscount, ctx.currency)),
            ],
          ),
        ),
        SizedBox(height: R.space(context, 12)),

        // Others
        _SectionCard(
          title: 'Others',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...ctx.misc.map(
                  (e) => _KeyVal(e.remarks ?? '-', _m(e.amount, ctx.currency))),
              _KeyVal('Other Discount',
                  '${input.otherDiscountPct.toStringAsFixed(0)}%'),
              _KeyVal('Other After Discount',
                  _m(math.otherAfterDiscount, ctx.currency)),
            ],
          ),
        ),
        SizedBox(height: R.space(context, 12)),

        // Totals
        _SectionCard(
          title: 'Totals',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KeyVal('Advance Paid', _m(ctx.advancePaid, ctx.currency)),
              _KeyVal('Balance Due (after discounts)',
                  _m(math.amountDueAfterDiscounts, ctx.currency)),
              _KeyVal('Payment Date', _d(input.paymentDate)),
              _KeyVal('Payee', input.payeeName),
              _KeyVal('Payment Type', input.paymentType),
            ],
          ),
        ),
        SizedBox(height: R.space(context, 24)),

        // Inline controls (no floating buttons)
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Emville.paper,
                  side: const BorderSide(color: emGreen),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveSize.of(context).h(14)),
                ),
                onPressed: onEdit,
                icon: const Icon(Icons.edit),
                label: const ResponsiveText('Edit',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
            SizedBox(width: R.space(context, 12)),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Emville.forest,
                  foregroundColor: Emville.paper,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveSize.of(context).h(14)),
                ),
                onPressed: onAttachProof,
                icon: Icon(proofPicked ? Icons.attachment : Icons.add_a_photo),
                label: ResponsiveText(
                    proofPicked ? 'Change Photo' : 'Attach Photo',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ],
        ),
        SizedBox(height: R.space(context, 12)),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Emville.forest,
              foregroundColor: Emville.paper,
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveSize.of(context).h(14)),
            ),
            onPressed: onConfirm,
            icon: const Icon(Icons.check_circle),
            label: const ResponsiveText('Confirm',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ),
        ),
      ],
    );
  }
}

class _BillPdfPreviewPage extends StatelessWidget {
  final String title;
  final Uint8List pdfBytes;
  const _BillPdfPreviewPage({required this.title, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: emGreen,
        foregroundColor: Colors.white,
        title: ResponsiveText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
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

// ============ SHARED ============

class _ExtraItem {
  final num amount;
  final String? remarks;
  final DateTime? billDate;
  final DateTime createdAt;

  _ExtraItem(
      {required this.amount,
      required this.createdAt,
      this.remarks,
      this.billDate});

  factory _ExtraItem.fromJson(Map<String, dynamic> json) {
    final amount = (json[kExtrasAmountCol] is num)
        ? json[kExtrasAmountCol] as num
        : num.tryParse('${json[kExtrasAmountCol]}') ?? 0;
    final createdRaw = json[kExtrasCreatedCol];
    final created = createdRaw is String
        ? DateTime.parse(createdRaw)
        : (createdRaw is DateTime ? createdRaw : DateTime.now());
    final remarks = (json[kExtrasRemarksCol] as String?)?.trim();
    final billDateRaw = json[kExtrasBillDateCol];
    final billDate = billDateRaw is String
        ? DateTime.tryParse(billDateRaw)
        : (billDateRaw is DateTime ? billDateRaw : null);
    return _ExtraItem(
        amount: amount,
        createdAt: created,
        remarks: remarks,
        billDate: billDate);
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;
  @override
  Widget build(BuildContext context) => BookingCard(children: [
        Text(title, style: Emville.heading(22)),
        const SizedBox(height: 13),
        child
      ]);
}

class _KeyVal extends StatelessWidget {
  const _KeyVal(this.k, this.v);
  final String k, v;
  @override
  Widget build(BuildContext context) => BookingValue(k, v);
}

class _ProofPickerDialog extends StatelessWidget {
  final ImagePicker picker;
  const _ProofPickerDialog({required this.picker});

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const ResponsiveText('Upload proof'),
      children: [
        SimpleDialogOption(
          onPressed: () async {
            final f = await picker.pickImage(
              source: ImageSource.camera,
              imageQuality: 85,
            );
            // ignore: use_build_context_synchronously
            Navigator.pop(context, f);
          },
          child: const ResponsiveText('Camera'),
        ),
        SimpleDialogOption(
          onPressed: () async {
            final f = await picker.pickImage(
              source: ImageSource.gallery,
              imageQuality: 85,
            );
            // ignore: use_build_context_synchronously
            Navigator.pop(context, f);
          },
          child: const ResponsiveText('Gallery'),
        ),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, null),
          child: const ResponsiveText('Cancel'),
        ),
      ],
    );
  }
}
// ---- utils ----

String _m(num v, String? currency) {
  final cur = (currency == null || currency.isEmpty) ? '' : '$currency ';
  return '$cur${v.toStringAsFixed(2)}';
}

String _d(DateTime? d) {
  if (d == null) return '—';
  return DateFormat('d MMM yyyy').format(d.toLocal());
}

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

num _asNum(dynamic v) => (v is num) ? v : (num.tryParse('${v ?? ''}') ?? 0);

// ---- Error block ----
// Put this in a shared place or top of the two files that need it.

// ---- Tables / buckets (reuse your constants if already defined) ----
//const kBookingsTable = 'booking_details';
//const kBookingIdCol  = 'id';
//const kFinalisedCol  = 'finalised';

//const kGuestReceiptsTable   = 'guest_receipts';
//const kGRAttachmentPathCol  = 'attachment_path';
//const kReceiptsPdfBucket    = 'guest_receipts_pdf';

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
      builder: (_) => _BillPdfPreviewPage(
        title: 'Final Bill',
        pdfBytes: bytes,
      ),
    ),
  );
  return true;
}
