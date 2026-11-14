import 'booking_style.dart';
// lib/features/bookings/bookings_add_bill.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:emville_pms/responsive/responsive_text.dart';

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
                backgroundColor: Emville.forest,
                foregroundColor: Emville.paper,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const ResponsiveText('Confirm',
                  style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted || _submitting) return;

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
  Widget build(BuildContext context) => FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) => BookingFrame(
              title: 'Add bill',
              eyebrow: 'Bookings / Billing',
              subtitle: 'Every extra, clearly accounted for.',
              actions: snapshot.hasError ||
                      snapshot.connectionState == ConnectionState.waiting
                  ? null
                  : FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add, size: 17),
                      label: Text(_submitting ? 'Adding…' : 'Add bill')),
              children: [
                if (snapshot.hasError)
                  EmvilleError(onRetry: () async {
                    setState(() {
                      _initFuture = _loadGuestName();
                    });
                  })
                else if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Emville.sage,
                          borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        const Icon(Icons.person_outline, size: 19),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(_guestNameCtrl.text,
                                style: Emville.heading(20))),
                        const Icon(Icons.lock_outline,
                            size: 14, color: Emville.muted)
                      ])),
                  bookingSection('Bill details'),
                  Form(
                      key: _formKey,
                      child: BookingCard(children: [
                        bookingLabel('Date'),
                        InkWell(
                            key: const ValueKey('bill-date'),
                            onTap: _submitting ? null : _pickDate,
                            child: InputDecorator(
                                decoration: bookingDecoration(),
                                child: Row(children: [
                                  Expanded(
                                      child: Text(
                                          _billDate == null
                                              ? 'Select bill date'
                                              : DateFormat('d MMM yyyy')
                                                  .format(_billDate!),
                                          style:
                                              const TextStyle(fontSize: 12))),
                                  const Icon(Icons.calendar_today_outlined,
                                      size: 16)
                                ]))),
                        const SizedBox(height: 18),
                        bookingLabel('Bill type'),
                        DropdownButtonFormField<String>(
                            key: const ValueKey('bill-type'),
                            initialValue: _billType,
                            isExpanded: true,
                            style: const TextStyle(
                                fontFamily: 'Roboto',
                                fontSize: 12,
                                color: Emville.ink),
                            decoration:
                                bookingDecoration(hint: 'Select bill type'),
                            items: const [
                              DropdownMenuItem(
                                  value: 'f&b', child: Text('Food & beverage')),
                              DropdownMenuItem(
                                  value: 'other', child: Text('Other'))
                            ],
                            onChanged: _submitting
                                ? null
                                : (v) => setState(() => _billType = v)),
                        const SizedBox(height: 18),
                        bookingLabel('Bill amount'),
                        TextFormField(
                            key: const ValueKey('bill-amount'),
                            controller: _amountCtrl,
                            enabled: !_submitting,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'))
                            ],
                            style: const TextStyle(fontSize: 12),
                            decoration: bookingDecoration(hint: '0.00')),
                        const SizedBox(height: 18),
                        bookingLabel('Remarks'),
                        TextFormField(
                            key: const ValueKey('bill-remarks'),
                            controller: _remarksCtrl,
                            enabled: !_submitting,
                            maxLines: 3,
                            style: const TextStyle(fontSize: 12),
                            decoration:
                                bookingDecoration(hint: 'e.g. Dinner · 500'))
                      ])),
                  const SizedBox(height: 14),
                  const Text('This bill will be added to this guest’s stay.',
                      style: TextStyle(
                          fontSize: 10, color: Emville.muted, height: 1.5)),
                ]
              ]));
}
