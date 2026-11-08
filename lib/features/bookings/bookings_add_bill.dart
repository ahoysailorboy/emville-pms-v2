// lib/features/bookings/bookings_add_bill.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:emville_pms/responsive/responsive_text.dart';
import 'package:emville_pms/responsive/responsive_theme.dart';
import 'package:emville_pms/responsive/responsive_size.dart';

// --- Emville brand colors ---
const emGreen = Color(0xFF103329);
const emGold = Color(0xFFD9A633);

// --- Tables / Columns ---
const kBookingsTable = 'booking_details';
const kBookingIdCol = 'id';
const kBookingGuestNameCol = 'guest_name';

const kExtrasTable = 'bookings_extras';
const kExtrasBookingIdCol = 'booking_id';
const kExtrasBillDateCol = 'bill_date';
const kExtrasGuestNameCol = 'guest_name';
const kExtrasTypeCol = 'bill_type'; // 'f&b' | 'other'
const kExtrasAmountCol = 'amount';
const kExtrasRemarksCol = 'remarks';

class BookingsAddBillPage extends StatefulWidget {
  final String bookingId;
  const BookingsAddBillPage({super.key, required this.bookingId});

  @override
  State<BookingsAddBillPage> createState() => _BookingsAddBillPageState();
}

class _BookingsAddBillPageState extends State<BookingsAddBillPage> {
  final _formKey = GlobalKey<FormState>();

  DateTime? _billDate;
  final _guestNameCtrl = TextEditingController();
  String? _billType; // 'f&b' | 'other'
  final _amountCtrl = TextEditingController();
  final _remarksCtrl = TextEditingController();

  bool _submitting = false;
  late Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _initFuture = _loadGuestName();
  }

  Future<void> _loadGuestName() async {
    final supa = Supabase.instance.client;
    final row = await supa
        .from(kBookingsTable)
        .select(kBookingGuestNameCol)
        .eq(kBookingIdCol, widget.bookingId)
        .maybeSingle();

    final name = (row?[kBookingGuestNameCol] as String?)?.trim();
    _guestNameCtrl.text = name ?? '';
  }

  @override
  void dispose() {
    _guestNameCtrl.dispose();
    _amountCtrl.dispose();
    _remarksCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _billDate ?? DateTime(now.year, now.month, now.day);
    final first = DateTime(now.year - 5, 1, 1);
    final last = DateTime(now.year, now.month, now.day); // no future dates

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      helpText: 'Select bill date',
      builder: (context, child) {
        // Ensure dialog uses Emville theme accents
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: emGreen,
                  secondary: emGold,
                ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(
          () => _billDate = DateTime(picked.year, picked.month, picked.day));
    }
  }

  String? _validate() {
    if (_billDate == null) return 'Please select the bill date.';
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    if (_billDate!.isAfter(todayOnly)) {
      return 'Bill date cannot be in the future.';
    }

    if (_guestNameCtrl.text.trim().isEmpty) return 'Guest name is empty.';
    if (_billType == null) return 'Please select a bill type.';

    final amountStr = _amountCtrl.text.trim();
    if (amountStr.isEmpty) return 'Please enter a bill amount.';
    final amount = num.tryParse(amountStr);
    if (amount == null) return 'Amount must be a number.';
    if (amount < 0) return 'Amount cannot be negative.';

    // remarks can be empty (allowed)
    return null;
  }

  Future<void> _submit() async {
    final err = _validate();
    if (err != null) {
      _showSnack(err, isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const ResponsiveText(
            'Confirm submission',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
          content: ResponsiveText(
            'Add this bill to the booking?',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const ResponsiveText('Cancel',
                  style: TextStyle(fontSize: 14)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: emGold,
                foregroundColor: emGreen,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const ResponsiveText('Confirm',
                  style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      setState(() => _submitting = true);
      final supa = Supabase.instance.client;

      final payload = {
        kExtrasBillDateCol: _billDate!.toIso8601String(), // bill_date
        kExtrasGuestNameCol: _guestNameCtrl.text.trim(), // guest_name
        kExtrasTypeCol: _billType, // 'f&b' | 'other'
        kExtrasBookingIdCol: widget.bookingId, // booking_id (uuid)
        kExtrasAmountCol: num.parse(_amountCtrl.text.trim()), // amount
        kExtrasRemarksCol: _remarksCtrl.text.trim(), // remarks
      };

      await supa.from(kExtrasTable).insert(payload);

      _showSnack('Bill added successfully.');
      if (mounted) Navigator.pop(context, true); // return to billing page
    } catch (e) {
      _showSnack('Failed to add bill: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: ResponsiveText(
          msg,
          style: const TextStyle(fontSize: 14),
        ),
        backgroundColor: isError ? Colors.redAccent : emGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = R.tokens(context);
    final rs = ResponsiveSize.of(context);
    final df = DateFormat('EEE, d MMM yyyy');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: emGreen,
        foregroundColor: Colors.white,
        title: const ResponsiveText(
          'Add bill',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      backgroundColor: const Color(0xFFF7F7F7),
      body: SafeArea(
        child: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _ErrorState(
                error: snap.error,
                onRetry: () async =>
                    setState(() => _initFuture = _loadGuestName()),
              );
            }

            return SingleChildScrollView(
              padding: EdgeInsets.all(tokens.padding),
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.disabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionCard(
                      title: 'Bill Details',
                      child: Column(
                        children: [
                          // Date (picker)
                          _FieldLabel('Date'),
                          InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: _decoration(hint: 'Select bill date'),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  ResponsiveText(
                                    _billDate == null
                                        ? '—'
                                        : df.format(_billDate!.toLocal()),
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const Icon(Icons.calendar_today,
                                      color: emGreen, size: 18),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(height: R.space(context, 12)),

                          // Guest Name (read-only)
                          _FieldLabel('Guest Name'),
                          TextFormField(
                            controller: _guestNameCtrl,
                            enabled: false,
                            style: TextStyle(fontSize: R.font(context, 14)),
                            decoration: _decoration(),
                          ),
                          SizedBox(height: R.space(context, 12)),

                          // Bill type
                          _FieldLabel('Bill type'),
                          DropdownButtonFormField<String>(
                            initialValue: _billType,
                            items: const [
                              DropdownMenuItem(
                                value: 'f&b',
                                child: ResponsiveText('F&B',
                                    style: TextStyle(fontSize: 14)),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: ResponsiveText('Other',
                                    style: TextStyle(fontSize: 14)),
                              ),
                            ],
                            onChanged: (v) => setState(() => _billType = v),
                            decoration: _decoration(hint: 'Select bill type'),
                          ),
                          SizedBox(height: R.space(context, 12)),

                          // Amount
                          _FieldLabel('Bill amount'),
                          TextFormField(
                            controller: _amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(
                                  r'^\d*\.?\d{0,2}')), // up to 2 decimals
                            ],
                            style: TextStyle(fontSize: R.font(context, 14)),
                            decoration: _decoration(hint: '0.00'),
                          ),
                          SizedBox(height: R.space(context, 12)),

                          // Remarks
                          _FieldLabel('Remarks'),
                          TextFormField(
                            controller: _remarksCtrl,
                            maxLines: 3,
                            style: TextStyle(fontSize: R.font(context, 14)),
                            decoration: _decoration(hint: 'e.g., Dinner - 500'),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: R.space(context, 24)),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: emGold,
                          foregroundColor: emGreen,
                          padding: EdgeInsets.symmetric(vertical: rs.h(14)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(tokens.radius),
                          ),
                          elevation: 1,
                        ),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: emGreen),
                              )
                            : const ResponsiveText(
                                'Submit',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 16),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // --- UI helpers ---
  InputDecoration _decoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.black38),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(
        horizontal: R.space(context, 12),
        vertical: R.space(context, 12),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0x22000000)),
        borderRadius: BorderRadius.circular(R.tokens(context).radius),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: emGreen, width: 1.2),
        borderRadius: BorderRadius.circular(R.tokens(context).radius),
      ),
      disabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0x11000000)),
        borderRadius: BorderRadius.circular(R.tokens(context).radius),
      ),
    );
  }
}

// --- Reusable bits ---
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: R.space(context, 6)),
      child: ResponsiveText(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: Colors.black87,
        ),
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
