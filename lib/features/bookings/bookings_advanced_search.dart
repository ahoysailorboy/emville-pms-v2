// lib/features/bookings/bookings_advanced_search.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Responsive system
import 'package:emville_pms/responsive/responsive_theme.dart';
import 'package:emville_pms/responsive/responsive_text.dart';
import 'package:emville_pms/responsive/responsive_size.dart';

// Edit page
import 'booking_edit.dart';

// PDF preview page (already defined in booking_details.dart)
import 'booking_details.dart' show BillPdfPreviewPage;

// Brand colors
const emGreen = Color(0xFF103329);
const emGold = Color(0xFFD9A633);

// ── DB: booking_details ──────────────────────────────────────────────────────
const kBookingsTable = 'booking_details';
const kBookingIdCol = 'id';
const kGuestNameCol = 'guest_name';
const kStatusCol = 'status';
const kCheckInCol = 'check_in';
const kCheckOutCol = 'check_out';
const kPaxCol = 'no_of_pax';
const kTotalPriceCol = 'total_price';
const kAdvancePaidCol = 'advance_paid';
const kBalanceCol = 'balance';
const kSourceCol = 'source';
const kNotesCol = 'notes';
const kCurrencyCol = 'currency';
const kFinalisedCol = 'finalised';

// ── guest_receipts + storage ────────────────────────────────────────────────
const kGuestReceiptsTable = 'guest_receipts';
const kGRBookingIdCol = 'booking_id';
const kGRAttachmentPathCol = 'attachment_path';
const kReceiptsPdfBucket = 'guest_receipts_pdf';

// Adjust these to EXACTLY match your DB enum/text values:
const kSourceOptions = <String>[
  'AirBnB',
  'Booking.com',
  'Instagram',
  'Other',
];

class BookingsAdvancedSearchPage extends StatefulWidget {
  const BookingsAdvancedSearchPage({super.key});

  @override
  State<BookingsAdvancedSearchPage> createState() =>
      _BookingsAdvancedSearchPageState();
}

class _BookingsAdvancedSearchPageState
    extends State<BookingsAdvancedSearchPage> {
  final _form = GlobalKey<FormState>();

  DateTime? _fromDate;
  DateTime? _toDate;
  final _guestCtrl = TextEditingController();
  final _keywordsCtrl = TextEditingController();

  /// Dropdown-selected source (null = Any)
  String? _sourceSelected;

  bool _loading = false;
  Object? _error;
  List<Map<String, dynamic>> _rows = [];

  final _df = DateFormat('d MMM yyyy');

  @override
  void dispose() {
    _guestCtrl.dispose();
    _keywordsCtrl.dispose();
    super.dispose();
  }

  // ── Date pickers ──────────────────────────────────────────────────────────
  Future<void> _pickFrom() async {
    final now = DateTime.now();
    final init = _fromDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        _fromDate = DateTime(picked.year, picked.month, picked.day);
        if (_toDate != null && _toDate!.isBefore(_fromDate!)) {
          _toDate = _fromDate;
        }
      });
    }
  }

  Future<void> _pickTo() async {
    final now = DateTime.now();
    final init = _toDate ?? _fromDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );
    if (picked != null) {
      setState(() {
        _toDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  void _clearAll() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _guestCtrl.clear();
      _keywordsCtrl.clear();
      _sourceSelected = null;
      _rows = [];
      _error = null;
    });
  }

  // ── Build a base SELECT that stays filterable (no .order here!) ───────────
  PostgrestFilterBuilder _baseSelect(SupabaseClient supa) {
    return supa.from(kBookingsTable).select(
          '$kBookingIdCol, $kGuestNameCol, $kStatusCol, $kCheckInCol, $kCheckOutCol, '
          '$kPaxCol, $kTotalPriceCol, $kAdvancePaidCol, $kBalanceCol, $kSourceCol, '
          '$kNotesCol, $kCurrencyCol, $kFinalisedCol',
        );
  }

  // ── Apply date overlap + guest + source filters (AND logic) ───────────────
  PostgrestFilterBuilder _applyCommonFilters(PostgrestFilterBuilder q) {
    // Overlap if: check_in <= to AND check_out >= from
    if (_fromDate != null && _toDate != null) {
      final fromIso = _fromDate!.toIso8601String();
      final toIso = _toDate!.toIso8601String();
      q = q.lte(kCheckInCol, toIso).gte(kCheckOutCol, fromIso);
    } else if (_fromDate != null) {
      final fromIso = _fromDate!.toIso8601String();
      q = q.gte(kCheckOutCol, fromIso);
    } else if (_toDate != null) {
      final toIso = _toDate!.toIso8601String();
      q = q.lte(kCheckInCol, toIso);
    }

    final guest = _guestCtrl.text.trim();
    if (guest.isNotEmpty) q = q.ilike(kGuestNameCol, '%$guest%');

    // Use equality for enum/text column to avoid ILIKE on enum
    // Use equality for enum/text column to avoid ILIKE on enum
    if (_sourceSelected != null && _sourceSelected!.isNotEmpty) {
      q = q.eq(kSourceCol, _sourceSelected!); // <-- non-null after the check
    }

    return q;
  }

  // ── Search (keywords search excludes source to avoid enum ILIKE) ──────────
  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _rows = [];
    });

    try {
      final supa = Supabase.instance.client;
      final kw = _keywordsCtrl.text.trim();

      if (kw.isEmpty) {
        final q = _applyCommonFilters(_baseSelect(supa))
            .order(kCheckInCol, ascending: true)
            .limit(200);
        final res = await q;
        final list = (res as List).cast<Map<String, dynamic>>();
        setState(() => _rows = list);
      } else {
        final safe = kw.replaceAll(',', ' ').trim();

        // guest_name + notes only (no source ILIKE on enum)
        final q1 = _applyCommonFilters(_baseSelect(supa))
            .ilike(kGuestNameCol, '%$safe%')
            .order(kCheckInCol, ascending: true)
            .limit(200);
        final q2 = _applyCommonFilters(_baseSelect(supa))
            .ilike(kNotesCol, '%$safe%')
            .order(kCheckInCol, ascending: true)
            .limit(200);

        final r1 = await q1;
        final r2 = await q2;

        final seen = <String>{};
        final merged = <Map<String, dynamic>>[];

        void addAll(dynamic raw) {
          for (final e in (raw as List).cast<Map<String, dynamic>>()) {
            final id = (e[kBookingIdCol] ?? '').toString();
            if (id.isEmpty || seen.contains(id)) continue;
            seen.add(id);
            merged.add(e);
          }
        }

        addAll(r1);
        addAll(r2);

        setState(() => _rows = merged);
      }
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Row actions ───────────────────────────────────────────────────────────
  Future<void> _confirmBooking(String bookingId) async {
    try {
      final supa = Supabase.instance.client;
      await supa
          .from(kBookingsTable)
          .update({kStatusCol: 'confirmed'}).eq(kBookingIdCol, bookingId);
      await _search(); // refresh
      _snack('Booking confirmed');
    } catch (e) {
      _snack('Failed to confirm: $e', true);
    }
  }

  Future<void> _openEdit(String bookingId) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => BookingEditPage(bookingId: bookingId)),
    );
    if (changed == true) {
      await _search();
    }
  }

  Future<void> _showBill(String bookingId, String guestName) async {
    try {
      final supa = Supabase.instance.client;

      final rec = await supa
          .from(kGuestReceiptsTable)
          .select(kGRAttachmentPathCol)
          .eq(kGRBookingIdCol, bookingId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final path = (rec != null) ? rec[kGRAttachmentPathCol] as String? : null;
      if (path == null || path.isEmpty) {
        _snack('No saved bill found for this booking.');
        return;
      }

      final Uint8List pdfBytes =
          await supa.storage.from(kReceiptsPdfBucket).download(path);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => BillPdfPreviewPage(
            title: '$guestName — Bill',
            pdfBytes: pdfBytes,
          ),
        ),
      );
    } catch (e) {
      _snack('Failed to open bill: $e', true);
    }
  }

  void _snack(String msg, [bool error = false]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : emGreen,
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: emGreen,
        foregroundColor: Colors.white,
        title: const ResponsiveText(
          'Advanced Booking Search',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(tokens.padding),
          children: [
            _SectionCard(
              title: 'Filters',
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Date range
                    Row(
                      children: [
                        Expanded(
                          child: _DateField(
                            label: 'From',
                            value: _fromDate == null
                                ? '—'
                                : _df.format(_fromDate!),
                            onTap: _pickFrom,
                          ),
                        ),
                        SizedBox(width: rs.w(10)),
                        Expanded(
                          child: _DateField(
                            label: 'To',
                            value: _toDate == null ? '—' : _df.format(_toDate!),
                            onTap: _pickTo,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: rs.h(10)),

                    _TextField(label: 'Guest name', controller: _guestCtrl),

                    // Source dropdown (instead of free-text)
                    _SourceDropdown(
                      value: _sourceSelected,
                      onChanged: (v) => setState(() => _sourceSelected = v),
                    ),

                    _TextField(
                      label: 'Keywords',
                      controller: _keywordsCtrl,
                      hint: 'Search in guest name and notes…',
                    ),

                    SizedBox(height: rs.h(12)),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: emGold,
                              foregroundColor: emGreen,
                              padding: EdgeInsets.symmetric(vertical: rs.h(14)),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(tokens.radius),
                              ),
                            ),
                            onPressed: _loading ? null : _search,
                            icon: const Icon(Icons.search),
                            label: const ResponsiveText(
                              'Search',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                        ),
                        SizedBox(width: rs.w(10)),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: emGreen,
                              side: const BorderSide(color: emGreen),
                              padding: EdgeInsets.symmetric(vertical: rs.h(14)),
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(tokens.radius),
                              ),
                            ),
                            onPressed: _loading ? null : _clearAll,
                            icon: const Icon(Icons.clear_all),
                            label: const ResponsiveText(
                              'Clear',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: rs.h(12)),
            if (_loading)
              const LinearProgressIndicator(minHeight: 3)
            else if (_error != null)
              _ErrorBox(error: _error, onRetry: _search)
            else
              _ResultsList(
                rows: _rows,
                onEdit: _openEdit,
                onConfirm: _confirmBooking,
                onShowBill: _showBill, // (bookingId, guestName)
              ),
          ],
        ),
      ),
    );
  }
}

// ── Results list (ExpansionTiles) ───────────────────────────────────────────

class _ResultsList extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onConfirm;
  final void Function(String bookingId, String guestName) onShowBill;

  const _ResultsList({
    required this.rows,
    required this.onEdit,
    required this.onConfirm,
    required this.onShowBill,
  });

  String _money(dynamic v, [String? c]) {
    if (v == null) return c == null ? '—' : '$c —';
    final num? n = (v is num) ? v : num.tryParse('$v');
    if (n == null) return c == null ? '—' : '$c —';
    return c == null || c.isEmpty
        ? n.toStringAsFixed(2)
        : '$c ${n.toStringAsFixed(2)}';
  }

  String _asStr(dynamic v) => (v == null || ('$v').trim().isEmpty) ? '—' : '$v';

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is String) {
      try {
        return DateTime.parse(v);
      } catch (_) {}
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final df = DateFormat('d MMM yyyy');

    Widget kv(String k, String v) => Padding(
          padding: EdgeInsets.symmetric(vertical: rs.h(3)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ResponsiveText(k,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: emGreen)),
              Flexible(
                child: ResponsiveText(v,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2),
              ),
            ],
          ),
        );

    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(rs.h(16)),
          child: const ResponsiveText(
            'No results.',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0x11000000)),
        borderRadius: BorderRadius.circular(R.tokens(context).radius),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows.length,
        separatorBuilder: (_, __) =>
            Divider(color: emGreen.withValues(alpha: 0.08), height: 1),
        itemBuilder: (context, i) {
          final b = rows[i];
          final id = b[kBookingIdCol] as String;
          final guest = _asStr(b[kGuestNameCol]);
          final status = _asStr(b[kStatusCol]).toLowerCase();
          final isFinalised = (b[kFinalisedCol] as bool?) == true;
          final isConfirmed = status == 'confirmed';

          final checkIn = _parseDate(b[kCheckInCol]);
          final checkOut = _parseDate(b[kCheckOutCol]);
          final checkInStr = checkIn == null ? '—' : df.format(checkIn);
          final checkOutStr = checkOut == null ? '—' : df.format(checkOut);

          final pax = b[kPaxCol];
          final source = _asStr(b[kSourceCol]);
          final total = _money(b[kTotalPriceCol], b[kCurrencyCol] as String?);
          final advance =
              _money(b[kAdvancePaidCol], b[kCurrencyCol] as String?);
          final balance = _money(b[kBalanceCol], b[kCurrencyCol] as String?);
          final notes = (b[kNotesCol] as String?) ?? '';

          return ExpansionTile(
            tilePadding: EdgeInsets.symmetric(
              horizontal: rs.w(12),
              vertical: rs.h(6),
            ),
            title: ResponsiveText(
              guest,
              style: const TextStyle(
                color: emGreen,
                fontWeight: FontWeight.w700,
              ),
              fontSize: 15,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: ResponsiveText(
              '$checkInStr → $checkOutStr',
              style: TextStyle(
                color: emGreen.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
              ),
              fontSize: 12,
            ),
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  rs.w(16),
                  rs.h(6),
                  rs.w(16),
                  rs.h(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    kv(
                        'Status',
                        status.isEmpty
                            ? '—'
                            : status[0].toUpperCase() + status.substring(1)),
                    kv('Check in', checkInStr),
                    kv('Check out', checkOutStr),
                    kv('No. of persons', pax == null ? '—' : '$pax'),
                    kv('Source', source),
                    kv('Total', total),
                    kv('Advance paid', advance),
                    kv('Balance', balance),
                    SizedBox(height: rs.h(8)),
                    const ResponsiveText('Notes',
                        style: TextStyle(
                            color: emGreen,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    SizedBox(height: rs.h(6)),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: emGreen.withValues(alpha: 0.03),
                        borderRadius:
                            BorderRadius.circular(R.tokens(context).radius),
                        border:
                            Border.all(color: emGreen.withValues(alpha: 0.18)),
                      ),
                      padding: EdgeInsets.all(rs.w(10)),
                      child: ResponsiveText(
                        notes.isNotEmpty ? notes : '—',
                        style: TextStyle(
                          color: emGreen.withValues(alpha: 0.9),
                          fontSize: R.font(context, 14),
                        ),
                      ),
                    ),
                    SizedBox(height: rs.h(12)),

                    // Actions
                    if (isFinalised)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emGold,
                            foregroundColor: emGreen,
                            padding: EdgeInsets.symmetric(
                                vertical: ResponsiveSize.of(context).h(14)),
                          ),
                          onPressed: () => onShowBill(id, guest),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const ResponsiveText('Show Bill',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: emGreen,
                                side: const BorderSide(color: emGreen),
                                padding: EdgeInsets.symmetric(
                                    vertical: ResponsiveSize.of(context).h(14)),
                              ),
                              onPressed: () => onEdit(id),
                              icon: const Icon(Icons.edit),
                              label: const ResponsiveText('Edit',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ),
                          ),
                          SizedBox(width: rs.w(10)),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isConfirmed ? Colors.grey : emGold,
                                foregroundColor: emGreen,
                                padding: EdgeInsets.symmetric(
                                    vertical: ResponsiveSize.of(context).h(14)),
                              ),
                              onPressed:
                                  isConfirmed ? null : () => onConfirm(id),
                              icon: const Icon(Icons.verified),
                              label: ResponsiveText(
                                  isConfirmed ? 'Confirmed' : 'Confirm',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Little UI atoms ─────────────────────────────────────────────────────────

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
                  fontWeight: FontWeight.w700, fontSize: 16, color: emGreen),
            ),
            SizedBox(height: ResponsiveSize.of(context).h(10)),
            child,
          ],
        ),
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? hint;
  const _TextField({required this.label, required this.controller, this.hint});

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final radius = R.tokens(context).radius;
    return Padding(
      padding: EdgeInsets.only(bottom: rs.h(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveText(label,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600, color: emGreen)),
          SizedBox(height: rs.h(6)),
          TextFormField(
            controller: controller,
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: rs.w(12),
                vertical: rs.h(10),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: const BorderSide(color: Color(0x22000000)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: const BorderSide(color: emGreen, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateField(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: emGreen),
        ),
        const Spacer(),
        TextButton.icon(
          icon: const Icon(Icons.calendar_today, color: emGreen, size: 16),
          label: ResponsiveText(value,
              style: const TextStyle(fontSize: 14, color: emGreen)),
          onPressed: onTap,
        ),
      ],
    );
  }
}

class _SourceDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _SourceDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final radius = R.tokens(context).radius;

    return Padding(
      padding: EdgeInsets.only(bottom: rs.h(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ResponsiveText(
            'Source',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: emGreen,
            ),
          ),
          SizedBox(height: rs.h(6)),
          DropdownButtonFormField<String?>(
            initialValue: value, // may be null (Any)
            isExpanded: true,
            items: <DropdownMenuItem<String?>>[
              const DropdownMenuItem<String?>(
                value: null,
                child: ResponsiveText(
                  'Any',
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
              ...kSourceOptions.map(
                (s) => DropdownMenuItem<String?>(
                  value: s,
                  child: ResponsiveText(
                    s,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),
              ),
            ],
            onChanged: onChanged,
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              contentPadding: EdgeInsets.symmetric(
                horizontal: rs.w(12),
                vertical: rs.h(10),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: const BorderSide(color: Color(0x22000000)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: const BorderSide(color: emGreen, width: 1.2),
              ),
            ),
            hint: const ResponsiveText(
              'Any',
              style: TextStyle(fontSize: 14, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  const _ErrorBox({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveSize.of(context).h(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: R.icon(context, 36), color: Colors.redAccent),
            SizedBox(height: ResponsiveSize.of(context).h(12)),
            ResponsiveText(
              'Something went wrong.\n${error ?? ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
            SizedBox(height: ResponsiveSize.of(context).h(16)),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: emGold, foregroundColor: emGreen),
              onPressed: onRetry,
              child: const ResponsiveText('Retry',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }
}
