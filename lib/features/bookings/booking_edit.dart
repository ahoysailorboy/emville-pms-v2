// lib/features/bookings/booking_edit.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Responsive system
import 'package:emville_pms/responsive/responsive_size.dart';
import 'package:emville_pms/responsive/responsive_text.dart';
import 'package:emville_pms/responsive/responsive_theme.dart';

// Brand colors
const emGreen = Color(0xFF103329);
const emGold = Color(0xFFD9A633);

// ---- DB ----
const kBookingsTable = 'booking_details';
const kBookingIdCol = 'id';
const kGuestNameCol = 'guest_name';
const kStatusCol = 'status';
const kCheckInCol = 'check_in';
const kCheckOutCol = 'check_out';
const kPaxCol = 'no_of_pax';
const kTotalPriceCol = 'total_price';
const kAdvancePaidCol = 'advance_paid';
//const kBalanceCol = 'balance';
const kSourceCol = 'source';
const kNotesCol = 'notes';
const kFinalisedCol = 'finalised';

class BookingEditPage extends StatefulWidget {
  final String bookingId;
  const BookingEditPage({super.key, required this.bookingId});

  @override
  State<BookingEditPage> createState() => _BookingEditPageState();
}

class _BookingEditPageState extends State<BookingEditPage> {
  final _form = GlobalKey<FormState>();

  bool _loading = true;
  Object? _error;
  Map<String, dynamic>? _row;

  // form fields
  late TextEditingController _guestName;
  late TextEditingController _source;
  late TextEditingController _pax;
  late TextEditingController _total;
  late TextEditingController _advance;
  // ignore: unused_field
  late TextEditingController _balance;
  late TextEditingController _notes;
  DateTime? _checkIn;
  DateTime? _checkOut;

  bool get _isFinalised => (_row?[kFinalisedCol] as bool?) == true;

  final _df = DateFormat('d MMM yyyy');

  @override
  void initState() {
    super.initState();
    _guestName = TextEditingController();
    _source = TextEditingController();
    _pax = TextEditingController();
    _total = TextEditingController();
    _advance = TextEditingController();
//    _balance = TextEditingController();
    _notes = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _guestName.dispose();
    _source.dispose();
    _pax.dispose();
    _total.dispose();
    _advance.dispose();
//    _balance.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final supa = Supabase.instance.client;
      final row = await supa
          .from(kBookingsTable)
          .select(
              '$kBookingIdCol, $kGuestNameCol, $kStatusCol, $kCheckInCol, $kCheckOutCol, $kPaxCol, $kTotalPriceCol, $kAdvancePaidCol, $kSourceCol, $kNotesCol, $kFinalisedCol')
          .eq(kBookingIdCol, widget.bookingId)
          .maybeSingle();

      if (row == null) {
        throw 'Booking not found';
      }

      _row = row;

      _guestName.text = (row[kGuestNameCol] as String?) ?? '';
      _source.text = (row[kSourceCol] as String?) ?? '';
      _pax.text = _toNumStr(row[kPaxCol]);
      _total.text = _toNumStr(row[kTotalPriceCol]);
      _advance.text = _toNumStr(row[kAdvancePaidCol]);
      // _balance.text = _toNumStr(row[kBalanceCol]);
      _notes.text = (row[kNotesCol] as String?) ?? '';
      _checkIn = _parseDate(row[kCheckInCol]);
      _checkOut = _parseDate(row[kCheckOutCol]);
    } catch (e) {
      _error = e;
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _toNumStr(dynamic v) {
    if (v == null) return '';
    if (v is num) return v.toString();
    final n = num.tryParse('$v');
    return n?.toString() ?? '';
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

  Future<void> _pickIn() async {
    final base = _checkIn ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 5),
      lastDate: DateTime(base.year + 5),
    );
    if (picked != null) {
      setState(
          () => _checkIn = DateTime(picked.year, picked.month, picked.day));
      if (_checkOut != null && _checkOut!.isBefore(_checkIn!)) {
        _checkOut = _checkIn;
      }
    }
  }

  Future<void> _pickOut() async {
    final base = _checkOut ?? (_checkIn ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(base.year - 5),
      lastDate: DateTime(base.year + 5),
    );
    if (picked != null) {
      setState(
          () => _checkOut = DateTime(picked.year, picked.month, picked.day));
    }
  }

  num _n(TextEditingController c) => num.tryParse(c.text.trim()) ?? 0;
  int _i(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  Future<void> _save() async {
    if (_form.currentState?.validate() != true) return;

    if (_checkIn == null || _checkOut == null) {
      _snack('Please select both Check-in and Check-out dates', true);
      return;
    }
    if (_checkOut!.isBefore(_checkIn!)) {
      _snack('Check-out cannot be before Check-in', true);
      return;
    }

    try {
      final supa = Supabase.instance.client;
      await supa.from(kBookingsTable).update({
        kCheckInCol: _checkIn!.toIso8601String(),
        kCheckOutCol: _checkOut!.toIso8601String(),
        kPaxCol: _i(_pax),
        kTotalPriceCol: _n(_total),
        kAdvancePaidCol: _n(_advance),
        //   kBalanceCol: _n(_balance),
        kSourceCol: _source.text.trim(),
        kNotesCol: _notes.text.trim(),
      }).eq(kBookingIdCol, widget.bookingId);

      _snack('Saved', false);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Failed to save: $e', true);
    }
  }

  Future<void> _cancelBooking() async {
    if (_isFinalised) {
      _snack('Cannot cancel a finalised booking.', true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: const ResponsiveText(
          'Cancel booking?',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        content: const ResponsiveText(
          'This will permanently delete the booking record.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const ResponsiveText('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const ResponsiveText(
              'Yes, delete',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final supa = Supabase.instance.client;
      await supa
          .from(kBookingsTable)
          .delete()
          .eq(kBookingIdCol, widget.bookingId);
      _snack('Booking cancelled', false);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack('Failed to cancel: $e', true);
    }
  }

  void _snack(String msg, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ResponsiveText(msg, style: const TextStyle(fontSize: 14)),
        backgroundColor: error ? Colors.redAccent : emGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    final rs = ResponsiveSize.of(context);

    final title = _loading
        ? 'Edit Booking'
        : 'Edit • ${(_row?[kGuestNameCol] as String? ?? 'Guest')}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: emGreen,
        foregroundColor: Colors.white,
        title: ResponsiveText(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Cancel booking (blocked if finalised)
          IconButton(
            tooltip: _isFinalised
                ? 'Finalised bookings cannot be cancelled'
                : 'Cancel booking',
            onPressed: _loading ? null : _cancelBooking,
            icon: const Icon(Icons.delete_forever),
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.all(rs.h(24)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: R.icon(context, 36), color: Colors.redAccent),
                        SizedBox(height: rs.h(12)),
                        ResponsiveText('Failed to load.\n$_error',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14)),
                        SizedBox(height: rs.h(16)),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: emGold,
                            foregroundColor: emGreen,
                          ),
                          onPressed: _load,
                          child: const ResponsiveText('Retry',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(tokens.padding),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionCard(
                            title: 'Dates',
                            child: Column(
                              children: [
                                _DateRow(
                                  label: 'Check-in',
                                  value: _checkIn == null
                                      ? '—'
                                      : _df.format(_checkIn!),
                                  onTap: _pickIn,
                                ),
                                SizedBox(height: rs.h(8)),
                                _DateRow(
                                  label: 'Check-out',
                                  value: _checkOut == null
                                      ? '—'
                                      : _df.format(_checkOut!),
                                  onTap: _pickOut,
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: rs.h(12)),
                          _SectionCard(
                            title: 'Booking',
                            child: Column(
                              children: [
                                _Field(
                                  label: 'Guest name',
                                  controller: _guestName,
                                  enabled: false, // immutable here
                                ),
                                _Field(
                                  label: 'Source',
                                  controller: _source,
                                ),
                                _Field(
                                  label: 'No. of persons',
                                  controller: _pax,
                                  keyboardType: TextInputType.number,
                                  validator: (t) {
                                    if (t == null || t.trim().isEmpty) {
                                      return null;
                                    }
                                    final v = int.tryParse(t.trim());
                                    if (v == null || v < 0) {
                                      return 'Enter a valid number';
                                    }
                                    return null;
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: rs.h(12)),
                          _SectionCard(
                            title: 'Amounts',
                            child: Column(
                              children: [
                                _Field(
                                  label: 'Total price',
                                  controller: _total,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  validator: _mustBeNonNegative,
                                ),
                                _Field(
                                  label: 'Advance paid',
                                  controller: _advance,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  validator: _mustBeNonNegative,
                                ),
                                /*_Field(
                                  label: 'Balance',
                                  controller: _balance,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  validator: _mustBeNonNegative,
                                ),*/
                              ],
                            ),
                          ),
                          SizedBox(height: rs.h(12)),
                          _SectionCard(
                            title: 'Notes',
                            child: _MultilineField(
                              controller: _notes,
                              hint: 'Special requests or remarks…',
                            ),
                          ),
                          SizedBox(height: rs.h(16)),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: emGold,
                                foregroundColor: emGreen,
                                padding:
                                    EdgeInsets.symmetric(vertical: rs.h(14)),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(tokens.radius),
                                ),
                              ),
                              onPressed: _save,
                              icon: const Icon(Icons.save),
                              label: const ResponsiveText(
                                'Save changes',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )),
    );
  }

  String? _mustBeNonNegative(String? t) {
    if (t == null || t.trim().isEmpty) return null;
    final v = num.tryParse(t.trim());
    if (v == null || v < 0) return 'Enter a non-negative number';
    return null;
  }
}

// ================= UI bits =================

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
            SizedBox(height: ResponsiveSize.of(context).h(10)),
            child,
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateRow(
      {required this.label, required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // ignore: unused_local_variable
    final rs = ResponsiveSize.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: emGreen),
        ),
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

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final bool enabled;

  const _Field({
    required this.label,
    required this.controller,
    this.keyboardType,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final radius = R.tokens(context).radius;
    return Padding(
      padding: EdgeInsets.only(bottom: rs.h(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveText(
            label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: emGreen),
          ),
          SizedBox(height: rs.h(6)),
          TextFormField(
            controller: controller,
            enabled: enabled,
            keyboardType: keyboardType,
            validator: validator,
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
          ),
        ],
      ),
    );
  }
}

class _MultilineField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  const _MultilineField({required this.controller, this.hint});

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final radius = R.tokens(context).radius;
    return TextFormField(
      controller: controller,
      maxLines: 4,
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
    );
  }
}
