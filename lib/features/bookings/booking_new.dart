import 'data/booking_edit_repository.dart' show bookingRoomCapacity;
// lib/features/bookings/booking_new.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:emville_pms/responsive/responsive.dart';
import 'package:emville_pms/supabase_call.dart' show supabaseCall;

/// Emville brand
const Color _emGreen = Color(0xFF103329);
const Color _emGold = Color(0xFFD9A633);
const Color _emBg = Color(0xFFF7F6F3);

/// ---- Config / DB constants -------------------------------------------------
const kPropertyTotalRooms =
    bookingRoomCapacity; // total inventory (adjust if needed)
const kReceiptsBucket = 'receipts';

const kBookingsTable = 'booking_details';
const kBookingIdCol = 'id';
const kStatusCol = 'status';
const kGuestNameCol = 'guest_name';
const kCheckInCol = 'check_in';
const kCheckOutCol = 'check_out';
const kPaxCol = 'no_of_pax';
const kRoomsCol = 'no_of_rooms';
const kSourceCol = 'source';
const kTotalPriceCol = 'total_price';
const kAdvancePaidCol = 'advance_paid';
const kAdvanceDateCol = 'advance_date';
const kCurrencyCol = 'currency';
const kNotesCol = 'notes';
const kPropertyIdCol = 'property_id';

const kUsersV = 'users_v'; // view
const kUsersUidCol = 'uid';
const kUsersFullNameCol = 'full_name';

const kMainLedgerTable = 'main_ledger';
const kMLDateCol = 'date';
const kMLAmountCol = 'amount';
const kMLTypeCol = 'transaction_type';
const kMLPayeeCol = 'payee_payer_name';
const kMLRemarksCol = 'remarks';
const kMLStatusCol = 'transaction_status';
const kMLCreatedByCol = 'created_by'; // full_name (text)
const kMLApprovedByCol = 'approved_by';
const kMLAttachmentPathCol = 'attachment_path';
const kMLPaymentModeCol = 'payment_mode'; // Card / Bank Transfer / UPI / Cash
const kMLCreatorUuidCol = 'creator_uuid';

class BookingNewPage extends StatefulWidget {
  const BookingNewPage({super.key});

  @override
  State<BookingNewPage> createState() => _BookingNewPageState();
}

class _BookingNewPageState extends State<BookingNewPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _guestName = TextEditingController();
  final _tariffCtrl = TextEditingController();
  final _advanceCtrl = TextEditingController(text: '0.00'); // default 0.00
  final _paxCtrl = TextEditingController(text: '2'); // 1..20
  final _notesCtrl = TextEditingController();
  final _propertyCtrl = TextEditingController(text: 'Chelamattom');
  final _userNameCtrl = TextEditingController();

  // Pickers / dropdowns
  DateTime? _checkIn;
  DateTime? _checkOut;

  // Advance controls (enabled only when _advanceValue > 0)
  DateTime? _advanceDate; // can be null if advance == 0
  String _paymentMode = 'Cash'; // used only if advance > 0
  Uint8List? _proofBytes; // optional
  String? _proofExt; // jpg/png

  String _status = 'confirmed'; // confirmed | enquiry | cancelled | unknown
  String _source = 'AirBnB'; // AirBnB | Booking.com | Instagram | Other
  int _noOfRooms = 4; // 4 = Full by default

  // Current user
  String? _userId; // auth uid (creator_uuid)
  String? _userFullName; // users_v.full_name (created_by)

  // Link back to email
  String? _linkedMessageId;

  bool _submitting = false;
  double _advanceValue = 0.0; // parsed from _advanceCtrl

  // We read nav arguments after first frame to ensure context is ready
  late Map<String, dynamic> _navArgs;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _advanceCtrl.addListener(_onAdvanceChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      _navArgs =
          (args is Map) ? args.cast<String, dynamic>() : <String, dynamic>{};
      _applyPrefill(_navArgs);
    });
  }

  @override
  void dispose() {
    _advanceCtrl.removeListener(_onAdvanceChanged);
    _guestName.dispose();
    _tariffCtrl.dispose();
    _advanceCtrl.dispose();
    _paxCtrl.dispose();
    _notesCtrl.dispose();
    _propertyCtrl.dispose();
    _userNameCtrl.dispose();
    super.dispose();
  }

  // ---------------- Prefill from check_email.dart ---------------------------

  void _applyPrefill(Map<String, dynamic> a) {
    // message_id linkage (so we can autosave it to bookings and link back)
    _linkedMessageId = _asString(a['email_message_id']) ??
        _asString(a['message_id']) ??
        _asString(a['gmail_message_id']);

    final preGuest = _asString(a['prefill_guest_name']);
    final preSource = _asString(a['prefill_source']);
    final preAdvance = _asNum(a['prefill_advance']); // may be payout amount
    final preStatus = _asString(a['prefill_status']); // 'confirmed' / 'enquiry'
    final prePax = _asInt(a['prefill_pax']);

    final cinStr = _asString(a['prefill_check_in']); // yyyy-MM-dd
    final coutStr = _asString(a['prefill_check_out']);

    if (preGuest != null) _guestName.text = preGuest;
    if (preSource != null && preSource.isNotEmpty) _source = preSource;

    if (preAdvance != null) {
      _advanceCtrl.text = preAdvance.toStringAsFixed(2);
      _advanceValue = preAdvance.toDouble(); // <- cast to double
    }

    if (preStatus != null && preStatus.isNotEmpty) {
      _status = preStatus; // default stays 'confirmed' otherwise
    }

    if (prePax != null && prePax >= 1 && prePax <= 20) {
      _paxCtrl.text = prePax.toString();
    }

    if (cinStr != null) _checkIn = _tryParseYmd(cinStr);
    if (coutStr != null) _checkOut = _tryParseYmd(coutStr);

    setState(() {}); // reflect prefill in UI
  }

  DateTime? _tryParseYmd(String s) {
    try {
      final d = DateTime.parse(s);
      return DateTime(d.year, d.month, d.day);
    } catch (_) {
      return null;
    }
  }

  String? _asString(Object? v) => v?.toString();
  int? _asInt(Object? v) => (v is int) ? v : int.tryParse('$v');
  num? _asNum(Object? v) {
    if (v == null) return null;
    if (v is num) return v;
    final s = '$v'.replaceAll(',', '');
    return num.tryParse(s);
  }

  // -------------------------------------------------------------------------

  bool get _advanceActive => _advanceValue > 0.0;

  void _onAdvanceChanged() {
    final v = _parseMoney(_advanceCtrl.text) ?? 0.0;
    if (v != _advanceValue) {
      setState(() {
        _advanceValue = v;
        if (!_advanceActive) {
          // reset dependent fields if user goes back to 0
          _advanceDate = null;
          _paymentMode = 'Cash';
          _proofBytes = null;
          _proofExt = null;
        }
      });
    }
  }

  Future<void> _loadCurrentUser() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    setState(() => _userId = user?.id);

    if (user?.id != null) {
      try {
        final rows = await supabaseCall(() async {
          return await client
              .from(kUsersV)
              .select(kUsersFullNameCol)
              .eq(kUsersUidCol, user!.id)
              .limit(1);
        });

        if (rows.isNotEmpty) {
          final name = rows.first[kUsersFullNameCol] as String?;
          if (name != null && mounted) {
            _userFullName = name;
            _userNameCtrl.text = name;
          }
        }
      } catch (_) {
        // ignore; not fatal
      }
    }
  }

  Future<void> _pickDate({required bool isCheckIn}) async {
    final now = DateTime.now();

    final initialDate = isCheckIn
        ? (_checkIn ?? DateTime(now.year, now.month, now.day))
        : (_checkOut ??
            (_checkIn ?? DateTime(now.year, now.month, now.day))
                .add(const Duration(days: 1)));

    final firstAllowed =
        DateTime(now.year, now.month, now.day - 1); // not before yesterday
    final lastAllowed = DateTime(now.year + 3);

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstAllowed,
      lastDate: lastAllowed,
      helpText: isCheckIn ? 'Select Check-in Date' : 'Select Check-out Date',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: _emGreen,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: _emGreen,
                ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkIn = DateTime(picked.year, picked.month, picked.day);
          if (_checkOut == null || _checkOut!.isBefore(_checkIn!)) {
            _checkOut = _checkIn!.add(const Duration(days: 1));
          }
        } else {
          _checkOut = DateTime(picked.year, picked.month, picked.day);
        }
      });
    }
  }

  Future<void> _pickAdvanceDate() async {
    if (!_advanceActive) return;
    final now = DateTime.now();
    final init = _advanceDate ?? DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: 'Select Advance Paid Date',
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: _emGreen,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: _emGreen,
                ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked != null) {
      setState(() {
        _advanceDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> _pickProofImage() async {
    if (!_advanceActive) return;
    final picker = ImagePicker();
    final file = await showDialog<XFile?>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Attach proof'),
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
            child: const Text('Camera'),
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
            child: const Text('Gallery'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (file != null) {
      final bytes = await file.readAsBytes();
      setState(() {
        _proofBytes = bytes;
        _proofExt = p.extension(file.path).toLowerCase().replaceAll('.', '');
        if ((_proofExt ?? '').isEmpty) _proofExt = 'jpg';
      });
    }
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Select date';
    try {
      return DateFormat('EEE, MMM d, yyyy').format(d);
    } catch (_) {
      return '${d.year}-${d.month}-${d.day}';
    }
  }

  double? _parseMoney(String s) {
    if (s.trim().isEmpty) return null;
    return double.tryParse(s.replaceAll(',', ''));
  }

  /// Returns the number of rooms available for the selected period at the property.
  /// Shows 0..kPropertyTotalRooms; only counts existing **confirmed** bookings.
  Future<int> _availableRoomsForRange({
    required String propertyId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) async {
    final client = Supabase.instance.client;

    // Correct overlap rule: existing.check_in < new.checkOut
    //                      AND existing.check_out > new.checkIn
    // Treats checkout as a free day, i.e. [check_in, check_out)
    final fromIso = checkIn.toIso8601String();
    final toIso = checkOut.toIso8601String();

    final rows = await client
        .from(kBookingsTable)
        .select(kRoomsCol)
        .eq(kPropertyIdCol, propertyId)
        .eq(kStatusCol, 'confirmed')
        .lt(kCheckInCol, toIso)
        .gt(kCheckOutCol, fromIso);

    int booked = 0;
    for (final r in (rows as List)) {
      final n = r[kRoomsCol];
      if (n is int) {
        booked += n;
      } else {
        final parsed = int.tryParse('$n');
        if (parsed != null) booked += parsed;
      }
    }

    final left = kPropertyTotalRooms - booked;
    return left.clamp(0, kPropertyTotalRooms);
  }

  // ---- SUBMIT --------------------------------------------------------------

  Future<void> _submit() async {
    final client = Supabase.instance.client;

    if (!_formKey.currentState!.validate()) return;
    if (_userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No user session found. Please sign in again.'),
        ),
      );
      return;
    }

    // If advance is active, ensure advance date exists
    if (_advanceActive && _advanceDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Advance Paid Date.')),
      );
      return;
    }

    // Basic required fields for availability check
    final checkIn = _checkIn;
    final checkOut = _checkOut;
    final propertyId = _propertyCtrl.text.trim();
    final requestedRooms = _noOfRooms;

    if (checkIn == null || checkOut == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select valid check-in and check-out dates.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // ---- Availability pre-check only for CONFIRMED bookings ---------------
      if (_status == 'confirmed') {
        final avail = await _availableRoomsForRange(
          propertyId: propertyId,
          checkIn: checkIn,
          checkOut: checkOut,
        );
        if (requestedRooms > avail) {
          // ignore: use_build_context_synchronously
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'There are $avail available rooms for the selected period. '
                'Change the number of rooms or the dates.',
              ),
            ),
          );
          setState(() => _submitting = false);
          return;
        }
      }

      // ---- Common field prep --------------------------------------------------
      final guestName = _guestName.text.trim();
      final tariff = _parseMoney(_tariffCtrl.text) ?? 0.0;
      final adv = _parseMoney(_advanceCtrl.text) ?? 0.0;
      final advance = adv <= 0 ? null : adv;
      final cinIso = checkIn.toIso8601String();
      final coutIso = checkOut.toIso8601String();

      String bookingId = '';

      // ---- Try upgrade an existing ENQUIRY to CONFIRMED (same guest+dates) ---
      // Only attempt upgrade when user picked "confirmed"
      if (_status == 'confirmed') {
        final List<dynamic> existingRows = await client
            .from(kBookingsTable)
            .select('id')
            .eq(kPropertyIdCol, propertyId)
            .eq(kStatusCol, 'enquiry')
            .eq(kGuestNameCol, guestName)
            .eq(kCheckInCol, cinIso)
            .eq(kCheckOutCol, coutIso)
            .limit(1);

        if (existingRows.isNotEmpty) {
          // Update existing enquiry to confirmed
          final existingId = existingRows.first['id']?.toString() ?? '';
          if (existingId.isNotEmpty) {
            await client.from(kBookingsTable).update({
              kStatusCol: 'confirmed',
              kSourceCol: _source,
              kPaxCol: int.tryParse(_paxCtrl.text.trim()),
              kRoomsCol: requestedRooms,
              kTotalPriceCol: tariff,
              kAdvancePaidCol: advance,
              kAdvanceDateCol:
                  _advanceActive ? _advanceDate?.toIso8601String() : null,
              kCurrencyCol: 'INR',
              'message_id': _linkedMessageId, // keep linkage
              kNotesCol: _notesCtrl.text.trim(),
              // leave property_id/check_in/check_out/guest_name as-is
            }).eq(kBookingIdCol, existingId);

            bookingId = existingId;
          }
        }
      }

      // ---- If not upgraded, do a fresh INSERT --------------------------------
      if (bookingId.isEmpty) {
        final insert = {
          'user_id': _userId,
          'status': _status,
          'check_in': cinIso,
          'check_out': coutIso,
          'guest_name': guestName,
          'no_of_pax': int.tryParse(_paxCtrl.text.trim()),
          'no_of_rooms': requestedRooms,
          'confidence': null,
          'source': _source,
          'total_price': tariff,
          'advance_paid': advance,
          'advance_date':
              _advanceActive ? _advanceDate?.toIso8601String() : null,
          'currency': 'INR',
          'message_id': _linkedMessageId, // <-- autosave linkage here
          'notes': _notesCtrl.text.trim(),
          'property_id': propertyId,
        };

        final inserted = await client
            .from(kBookingsTable)
            .insert(insert)
            .select('id')
            .single();
        bookingId = inserted['id']?.toString() ?? '';
      }

      // ---- Link back to emails_ingested (if message_id present) --------------
      final msgId = _linkedMessageId; // local final for promotion
      if (msgId != null && msgId.isNotEmpty && bookingId.isNotEmpty) {
        try {
          await client.from('emails_ingested').update({
            'booking_id': bookingId,
            'linked_at': DateTime.now().toIso8601String(),
          }).eq('message_id', msgId);
        } catch (_) {
          // non-fatal
        }
      }

      // ---- If advance > 0, add to main_ledger --------------------------------
      if (_advanceActive && bookingId.isNotEmpty) {
        String? proofPath;
        if (_proofBytes != null) {
          final ts = DateTime.now().millisecondsSinceEpoch;
          final ext = _proofExt ?? 'jpg';
          final path = 'booking_$bookingId/advance_$ts.$ext';
          await client.storage
              .from(kReceiptsBucket)
              .uploadBinary(path, _proofBytes!);
          proofPath = path;
        }

        final remarks =
            'Advance for stay from ${_fmtDate(checkIn)} to ${_fmtDate(checkOut)}';

        await client.from(kMainLedgerTable).insert({
          kMLDateCol: _advanceDate!.toIso8601String(),
          kMLAmountCol: _advanceValue,
          kMLTypeCol: 'income',
          kMLPayeeCol: guestName,
          kMLRemarksCol: remarks,
          kMLStatusCol: 'pending',
          kMLCreatedByCol: _userFullName, // text name
          kMLApprovedByCol: null,
          kMLAttachmentPathCol: proofPath,
          kMLPaymentModeCol: _paymentMode,
          kMLCreatorUuidCol: _userId,
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(bookingId.isNotEmpty
                ? 'Booking ${_status == "confirmed" ? "saved" : "added"}'
                : 'Booking added')),
      );
      Navigator.of(context).pop(bookingId);
    } catch (e) {
      // Friendly handling if DB exclusion constraint still triggers
      final msg = e.toString();
      final looksLikeExclusion = msg.contains('23P01') ||
          msg.contains('exclusion') ||
          msg.contains('no_overlapping_confirmed_bookings_per_property');

      if (looksLikeExclusion) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'There are 0 available rooms for the selected period. '
              'Change the number of rooms or the dates.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add booking: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---- UI ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    // ignore: unused_local_variable
    final moneyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 2);

    return ResponsiveScaffold(
      backgroundColor: _emBg,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const ResponsiveText(
          'New Booking',
          style: TextStyle(fontWeight: FontWeight.w700, color: _emGold),
          fontSize: 18,
        ),
        elevation: 0,
        foregroundColor: _emGold,
        backgroundColor: _emGreen,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: rs.space(24)),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _CardSection(
                title: 'Stay',
                children: [
                  _DateField(
                    label: 'Check In Date',
                    valueText: _fmtDate(_checkIn),
                    onTap: () => _pickDate(isCheckIn: true),
                    validator: () {
                      if (_checkIn == null) {
                        return 'Please select check-in date';
                      }
                      final prevDay =
                          DateTime.now().subtract(const Duration(days: 1));
                      if (_checkIn!.isBefore(
                          DateTime(prevDay.year, prevDay.month, prevDay.day))) {
                        return 'Check-in cannot be before yesterday';
                      }
                      return null;
                    },
                  ),
                  _DateField(
                    label: 'Check Out Date',
                    valueText: _fmtDate(_checkOut),
                    onTap: () => _pickDate(isCheckIn: false),
                    validator: () {
                      if (_checkOut == null) {
                        return 'Please select check-out date';
                      }
                      if (_checkIn != null && _checkOut!.isBefore(_checkIn!)) {
                        return 'Check-out cannot be before check-in';
                      }
                      return null;
                    },
                  ),
                  _DropdownField<String>(
                    label: 'Status',
                    value: _status,
                    items: const [
                      'confirmed',
                      'enquiry',
                      'cancelled',
                      'unknown'
                    ],
                    onChanged: (v) =>
                        setState(() => _status = v ?? 'confirmed'),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Select a status' : null,
                  ),
                ],
              ),
              _CardSection(
                title: 'Guest',
                children: [
                  _TextField(
                    label: 'Guest Name',
                    controller: _guestName,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter guest name'
                        : null,
                  ),
                  // Number of persons as NUMBER FIELD with validation 1..20
                  _NumberField(
                    label: 'Number of persons',
                    controller: _paxCtrl,
                    min: 1,
                    max: 20,
                  ),
                  _DropdownField<int>(
                    label: 'Number of rooms',
                    value: _noOfRooms,
                    items: const [4, 1, 2, 3],
                    itemLabelBuilder: (n) => n == 4 ? 'Full (4)' : '$n',
                    onChanged: (v) => setState(() => _noOfRooms = v ?? 4),
                    validator: (v) => (v == null) ? 'Select rooms' : null,
                  ),
                ],
              ),
              _CardSection(
                title: 'Booking & Payment',
                children: [
                  _DropdownField<String>(
                    label: 'Booking source',
                    value: _source,
                    items: const [
                      'AirBnB',
                      'Booking.com',
                      'Instagram',
                      'Other'
                    ],
                    onChanged: (v) => setState(() => _source = v ?? 'AirBnB'),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Select booking source'
                        : null,
                  ),
                  _MoneyField(
                    label: 'Tariff (INR)',
                    controller: _tariffCtrl,
                    validator: (v) {
                      final val = _parseMoney(v ?? '');
                      if (val == null) return 'Enter tariff';
                      if (val < 0) return 'Tariff cannot be negative';
                      return null;
                    },
                  ),
                  // Advance (controls activation of the fields below)
                  _MoneyField(
                    label: 'Advance paid (INR)',
                    controller: _advanceCtrl,
                    validator: (v) {
                      final adv = _parseMoney(v ?? '');
                      if (adv == null) return 'Enter advance (0.00 if none)';
                      if (adv < 0) return 'Advance cannot be negative';
                      final tar = _parseMoney(_tariffCtrl.text) ?? 0.0;
                      if (adv > tar) return 'Advance cannot exceed tariff';
                      return null;
                    },
                  ),

                  // Dependent controls (enabled only if _advanceActive)
                  Opacity(
                    opacity: _advanceActive ? 1.0 : 0.45,
                    child: IgnorePointer(
                      ignoring: !_advanceActive,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DateField(
                            label: 'Advance Paid Date',
                            valueText: _fmtDate(_advanceDate),
                            onTap: _pickAdvanceDate,
                            validator: () {
                              if (!_advanceActive) return null;
                              if (_advanceDate == null) {
                                return 'Select advance paid date';
                              }
                              return null;
                            },
                          ),
                          _DropdownField<String>(
                            label: 'Payment mode',
                            value: _paymentMode,
                            items: const [
                              'Card',
                              'Bank Transfer',
                              'UPI',
                              'Cash'
                            ],
                            onChanged: (v) =>
                                setState(() => _paymentMode = v ?? 'Cash'),
                            validator: (v) => !_advanceActive
                                ? null
                                : (v == null || v.isEmpty)
                                    ? 'Select payment mode'
                                    : null,
                          ),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _emGreen,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: _pickProofImage,
                                icon: const Icon(Icons.attach_file),
                                label: Text(
                                  _proofBytes == null
                                      ? 'Attach Photo (optional)'
                                      : 'Change Photo',
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (_proofBytes != null)
                                const Icon(Icons.check_circle, color: _emGreen),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  _TextArea(
                    label: 'Special requests',
                    controller: _notesCtrl,
                  ),
                ],
              ),
              _CardSection(
                title: 'Property & User',
                children: [
                  _TextField(
                    label: 'Property ID',
                    controller: _propertyCtrl,
                    readOnly: true,
                  ),
                  _TextField(
                    label: 'User Name',
                    controller: _userNameCtrl,
                    readOnly: true,
                  ),
                ],
              ),
              SizedBox(height: rs.space(12)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: const ResponsiveText(
                    'Submit',
                    style: TextStyle(fontWeight: FontWeight.w700),
                    fontSize: 16,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _emGreen,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                      vertical: rs.space(14),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(R.radius(context, 12)),
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ------------ Reusable small widgets (styled, responsive) ------------

class _CardSection extends StatelessWidget {
  const _CardSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: rs.space(12)),
      padding: EdgeInsets.all(rs.w(12)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(R.radius(context, 16)),
        border: Border.all(color: _emGreen.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ResponsiveText(
            title,
            style:
                const TextStyle(fontWeight: FontWeight.w700, color: _emGreen),
            fontSize: 16,
          ),
          SizedBox(height: rs.space(10)),
          ...children.map((w) => Padding(
                padding: EdgeInsets.only(bottom: rs.space(10)),
                child: w,
              )),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.valueText,
    required this.onTap,
    this.validator,
  });

  final String label;
  final String valueText;
  final VoidCallback onTap;
  final String? Function()? validator;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    final error = validator?.call();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
          fontSize: 14,
        ),
        SizedBox(height: rs.space(6)),
        Material(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.radius(context, 12)),
            side: BorderSide(
                color: error == null
                    ? _emGreen.withValues(alpha: 0.18)
                    : Colors.redAccent),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(R.radius(context, 12)),
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: rs.w(12), vertical: rs.h(14)),
              child: Row(
                children: [
                  const Icon(Icons.date_range, color: _emGreen),
                  SizedBox(width: rs.w(10)),
                  Expanded(
                    child: ResponsiveText(
                      valueText,
                      style: const TextStyle(color: _emGreen),
                      fontSize: 14,
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: _emGreen),
                ],
              ),
            ),
          ),
        ),
        if (error != null) ...[
          SizedBox(height: rs.space(4)),
          Text(error,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        ]
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.itemLabelBuilder,
  });

  final String label;
  final T value;
  final List<T> items;
  final void Function(T?) onChanged;
  final String? Function(T?)? validator;
  final String Function(T value)? itemLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
          fontSize: 14,
        ),
        SizedBox(height: rs.space(6)),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items
              .map(
                (e) => DropdownMenuItem<T>(
                  value: e,
                  child: ResponsiveText(
                    itemLabelBuilder != null ? itemLabelBuilder!(e) : '$e',
                    style: const TextStyle(color: _emGreen),
                    fontSize: 14,
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          validator: validator,
          decoration: InputDecoration(
            contentPadding:
                EdgeInsets.symmetric(horizontal: rs.w(12), vertical: rs.h(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: BorderSide(color: _emGreen.withValues(alpha: 0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: const BorderSide(color: _emGreen),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: const BorderSide(color: Colors.redAccent),
            ),
          ),
          iconEnabledColor: _emGreen,
          dropdownColor: Colors.white,
        ),
      ],
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.label,
    required this.controller,
    this.readOnly = false,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final bool readOnly;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
          fontSize: 14,
        ),
        SizedBox(height: rs.space(6)),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          validator: validator,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                EdgeInsets.symmetric(horizontal: rs.w(12), vertical: rs.h(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: BorderSide(color: _emGreen.withValues(alpha: 0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: const BorderSide(color: _emGreen),
            ),
          ),
          style: const TextStyle(color: _emGreen),
        ),
      ],
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    required this.min,
    required this.max,
  });

  final String label;
  final TextEditingController controller;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
          fontSize: 14,
        ),
        SizedBox(height: rs.space(6)),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: false,
            signed: false,
          ),
          validator: (v) {
            final n = int.tryParse((v ?? '').trim());
            if (n == null) return 'Enter a number ($min–$max)';
            if (n < min || n > max) return 'Must be between $min and $max';
            return null;
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                EdgeInsets.symmetric(horizontal: rs.w(12), vertical: rs.h(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: BorderSide(color: _emGreen.withValues(alpha: 0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: const BorderSide(color: _emGreen),
            ),
          ),
          style: const TextStyle(color: _emGreen),
        ),
      ],
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.label,
    required this.controller,
    // ignore: unused_element_parameter
    this.hint,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
          fontSize: 14,
        ),
        SizedBox(height: rs.space(6)),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: false,
          ),
          validator: validator,
          decoration: InputDecoration(
            hintText: hint ?? '0.00',
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                EdgeInsets.symmetric(horizontal: rs.w(12), vertical: rs.h(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: BorderSide(color: _emGreen.withValues(alpha: 0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: const BorderSide(color: _emGreen),
            ),
          ),
          style: const TextStyle(color: _emGreen),
        ),
      ],
    );
  }
}

class _TextArea extends StatelessWidget {
  const _TextArea({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ResponsiveText(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _emGreen),
          fontSize: 14,
        ),
        SizedBox(height: rs.space(6)),
        TextFormField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.all(rs.w(12)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: BorderSide(color: _emGreen.withValues(alpha: 0.18)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(R.radius(context, 12)),
              borderSide: const BorderSide(color: _emGreen),
            ),
          ),
          style: const TextStyle(color: _emGreen),
        ),
      ],
    );
  }
}
