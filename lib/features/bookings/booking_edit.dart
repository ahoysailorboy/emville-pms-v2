import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'booking_style.dart';
import 'data/booking_edit_repository.dart';

class BookingEditPage extends StatefulWidget {
  const BookingEditPage({super.key, required this.bookingId});
  final String bookingId;
  @override
  State<BookingEditPage> createState() => _BookingEditPageState();
}

class _BookingEditPageState extends State<BookingEditPage> {
  final _form = GlobalKey<FormState>();
  final _repository = BookingEditRepository(Supabase.instance.client);
  final _fields = <String, TextEditingController>{
    for (final field in [
      'guest_name',
      'no_of_pax',
      'no_of_rooms',
      'property_id',
      'currency',
      'total_price',
      'advance_paid',
      'notes'
    ])
      field: TextEditingController()
  };
  Map<String, dynamic>? _original;
  DateTime? _checkIn, _checkOut, _advanceDate;
  String _status = 'confirmed', _source = 'Other';
  bool _loading = true,
      _saving = false,
      _allowExit = false,
      _discardOpen = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final c in _fields.values) {
      c.addListener(_changed);
    }
    _load();
  }

  void _changed() {
    if (mounted && !_loading) setState(() {});
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await _repository.load(widget.bookingId);
      if (!mounted) return;
      if (row == null) throw const BookingEditException('Booking not found.');
      _original = row;
      for (final field in _fields.keys) {
        _fields[field]!.text =
            row[field]?.toString() ?? (field == 'advance_paid' ? '0' : '');
      }
      _status = row['status']?.toString() ?? 'unknown';
      _source = row['source']?.toString() ?? 'Other';
      _checkIn = bookingDate(row['check_in']);
      _checkOut = bookingDate(row['check_out']);
      _advanceDate = bookingDate(row['advance_date']);
    } catch (_) {
      if (mounted) _error = 'Could not load this booking. Please try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _values() => {
        for (final field in ['guest_name', 'property_id', 'notes'])
          field: _fields[field]!.text.trim(),
        'status': _status,
        'source': _source,
        'currency': _fields['currency']!.text.trim().toUpperCase(),
        for (final field in ['no_of_pax', 'no_of_rooms'])
          field: int.tryParse(_fields[field]!.text.trim()),
        for (final field in ['total_price', 'advance_paid'])
          field: num.tryParse(_fields[field]!.text.replaceAll(',', '').trim()),
        'check_in': serializeBookingDate(_checkIn, _original?['check_in']),
        'check_out': serializeBookingDate(_checkOut, _original?['check_out']),
        'advance_date':
            serializeBookingDate(_advanceDate, _original?['advance_date']),
      };
  bool get _dirty =>
      _original != null && bookingEditPatch(_original!, _values()).isNotEmpty;
  Future<void> _leave() async {
    if (_saving || _discardOpen) return;
    if (!_dirty) {
      Navigator.pop(context);
      return;
    }
    _discardOpen = true;
    final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('Discard changes?', style: Emville.heading(24)),
                content:
                    const Text('Your booking changes have not been saved.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep editing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Discard'))
                ]));
    _discardOpen = false;
    if (discard == true && mounted) _finish(false);
  }

  void _finish(bool saved) {
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, saved);
    });
  }

  Future<void> _pickDate(String field, {bool time = false}) async {
    final current = field == 'check_in'
        ? _checkIn
        : field == 'check_out'
            ? _checkOut
            : _advanceDate;
    final base = current ?? DateTime.now();
    DateTime? result;
    if (time) {
      final picked = await showTimePicker(
          context: context, initialTime: TimeOfDay.fromDateTime(base));
      if (picked != null) {
        result = DateTime(
            base.year, base.month, base.day, picked.hour, picked.minute);
      }
    } else {
      final now = DateTime.now();
      final initial = field == 'advance_date' && base.isAfter(now) ? now : base;
      final date = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: DateTime(initial.year - 20),
          lastDate: field == 'advance_date' ? now : DateTime(initial.year + 20),
          helpText: field == 'advance_date'
              ? 'Advance payment date'
              : field == 'check_in'
                  ? 'Check-in date'
                  : 'Check-out date');
      if (date != null) {
        result = DateTime(date.year, date.month, date.day, base.hour,
            base.minute, base.second, base.millisecond, base.microsecond);
      }
    }
    if (result != null && mounted) {
      setState(() {
        if (field == 'check_in') {
          _checkIn = result;
        } else if (field == 'check_out') {
          _checkOut = result;
        } else {
          _advanceDate = result;
        }
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _original == null) return;
    _form.currentState?.validate();
    final values = _values();
    try {
      validateBookingEdit(_original!, values);
    } on BookingEditException catch (error) {
      _snack(error.message);
      return;
    }
    final patch = bookingEditPatch(_original!, values);
    if (patch.isEmpty) {
      _snack('No changes to save.');
      return;
    }
    final financial = patch.keys.any(
        ['total_price', 'advance_paid', 'advance_date', 'currency'].contains);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title:
                    Text('Save booking changes?', style: Emville.heading(24)),
                content: Text(
                    'Update ${values['guest_name']}’s booking?${financial || _original!['finalised'] == true ? '\n\nReview any related receipt or ledger corrections separately.' : ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Keep editing')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Save changes'))
                ]));
    if (confirmed != true || !mounted || _saving) return;
    setState(() => _saving = true);
    try {
      await _repository.save(_original!, patch);
      if (mounted) {
        _snack('Booking updated.');
        _finish(true);
      }
    } on BookingEditException catch (error) {
      _snack(error.message);
    } on PostgrestException catch (error) {
      _snack(error.code == '42501'
          ? 'You do not have permission to edit this booking.'
          : 'Could not save the booking. Check the details and try again.');
    } catch (_) {
      _snack(
          'Could not save the booking. Your changes are still here. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Widget _input(String field, String label,
          {bool number = false, int lines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bookingLabel(label),
        TextFormField(
            key: ValueKey('edit-$field'),
            controller: _fields[field],
            enabled: !_saving,
            keyboardType: number
                ? const TextInputType.numberWithOptions(decimal: true)
                : null,
            maxLines: lines,
            style: const TextStyle(fontSize: 12),
            decoration: bookingDecoration(),
            validator: (s) => field == 'notes' || s?.trim().isNotEmpty == true
                ? null
                : 'Required')
      ]);
  Widget _select(String field, String label, String value, List<String> options,
          ValueChanged<String> onChanged) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bookingLabel(label),
        DropdownButtonFormField<String>(
            key: ValueKey('edit-$field'),
            initialValue: value,
            isExpanded: true,
            style: const TextStyle(
                fontFamily: 'Roboto', fontSize: 12, color: Emville.ink),
            decoration: bookingDecoration(),
            items: [
              for (final item in {...options, value})
                DropdownMenuItem(value: item, child: Text(item))
            ],
            onChanged: _saving
                ? null
                : (s) {
                    if (s != null) setState(() => onChanged(s));
                  })
      ]);
  Widget _date(String field, String label, DateTime? value,
          {bool time = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        bookingLabel(label),
        InkWell(
            key: ValueKey('edit-$field${time ? '-time' : ''}'),
            onTap: _saving ? null : () => _pickDate(field, time: time),
            child: InputDecorator(
                decoration: bookingDecoration(),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          value == null
                              ? 'Select date'
                              : DateFormat(time ? 'h:mm a' : 'd MMM yyyy')
                                  .format(value),
                          style: const TextStyle(fontSize: 12))),
                  Icon(time ? Icons.access_time : Icons.calendar_today_outlined,
                      size: 16)
                ])))
      ]);
  Widget _pair(Widget a, Widget b) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b)
      ]);
  @override
  Widget build(BuildContext context) {
    final parsedTotal =
        num.tryParse(_fields['total_price']!.text.replaceAll(',', ''));
    final parsedAdvance =
        num.tryParse(_fields['advance_paid']!.text.replaceAll(',', ''));
    final total = parsedTotal?.isFinite == true ? parsedTotal! : 0;
    final advance = parsedAdvance?.isFinite == true ? parsedAdvance! : 0;
    return PopScope(
        canPop: _allowExit || (!_dirty && !_saving),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Form(
            key: _form,
            child: BookingFrame(
                title: 'Edit booking',
                subtitle: 'Update the details of this guest’s stay.',
                actions: _loading || _error != null
                    ? null
                    : Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: _saving ? null : _leave,
                                child: const Text('Cancel'))),
                        const SizedBox(width: 10),
                        Expanded(
                            child: FilledButton.icon(
                                onPressed: _saving ? null : _save,
                                icon: _saving
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : const Icon(Icons.check_outlined,
                                        size: 16),
                                label:
                                    Text(_saving ? 'Saving…' : 'Save changes')))
                      ]),
                children: [
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null)
                    EmvilleError(message: _error!, onRetry: _load)
                  else ...[
                    if (_original!['finalised'] == true) ...[
                      const EmvilleCallout(
                          child: Text(
                              'This booking has a finalised bill. Changes here do not replace the saved receipt. Review related corrections separately.')),
                      const SizedBox(height: 16)
                    ],
                    BookingCard(children: [
                      Text('Guest & status', style: Emville.heading(22)),
                      const SizedBox(height: 16),
                      _input('guest_name', 'Guest name'),
                      const SizedBox(height: 16),
                      _select('status', 'Status', _status, bookingStatuses,
                          (s) => _status = s),
                      const SizedBox(height: 16),
                      _select('source', 'Booking source', _source,
                          bookingSources, (s) => _source = s)
                    ]),
                    bookingSection('The stay'),
                    BookingCard(children: [
                      bookingDateOnly(_original!['check_in'])
                          ? _date('check_in', 'Check-in date', _checkIn)
                          : _pair(
                              _date('check_in', 'Check-in date', _checkIn),
                              _date('check_in', 'Check-in time', _checkIn,
                                  time: true)),
                      const SizedBox(height: 16),
                      bookingDateOnly(_original!['check_out'])
                          ? _date('check_out', 'Check-out date', _checkOut)
                          : _pair(
                              _date('check_out', 'Check-out date', _checkOut),
                              _date('check_out', 'Check-out time', _checkOut,
                                  time: true)),
                      const SizedBox(height: 16),
                      _pair(_input('no_of_rooms', 'Rooms (1–4)', number: true),
                          _input('no_of_pax', 'Guests (1–20)', number: true)),
                      const SizedBox(height: 16),
                      _input('property_id', 'Property')
                    ]),
                    bookingSection('Payment details'),
                    BookingCard(children: [
                      _input('currency', 'Currency (e.g. INR)'),
                      const SizedBox(height: 16),
                      _pair(_input('total_price', 'Total price', number: true),
                          _input('advance_paid', 'Advance paid', number: true)),
                      const SizedBox(height: 16),
                      _date(
                          'advance_date', 'Advance payment date', _advanceDate),
                      if (_advanceDate != null)
                        Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _advanceDate = null),
                                child: const Text('Clear date',
                                    style: TextStyle(fontSize: 10)))),
                      const SizedBox(height: 14),
                      const Divider(height: 1),
                      BookingValue(
                          'Calculated balance',
                          bookingMoney(total - advance,
                              _fields['currency']!.text.trim().toUpperCase())),
                      const Text(
                          'Review receipt and account entries separately when correcting payment details.',
                          style: TextStyle(
                              fontSize: 10, height: 1.5, color: Emville.muted))
                    ]),
                    bookingSection('Notes'),
                    BookingCard(children: [
                      _input('notes', 'Special requests or notes', lines: 4)
                    ]),
                    const SizedBox(height: 18),
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Record information · read-only',
                            style:
                                TextStyle(fontSize: 11, color: Emville.muted)),
                        children: [
                          for (final field in [
                            'id',
                            'user_id',
                            'message_id',
                            'confidence',
                            'finalised',
                            'created_at',
                            'updated_at',
                            'stay_range'
                          ])
                            BookingValue(field.replaceAll('_', ' '),
                                _original![field]?.toString() ?? '—')
                        ]),
                  ]
                ])));
  }
}
