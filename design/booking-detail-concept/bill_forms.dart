// Design-only fixtures. These forms never save records or take payments.
import 'package:flutter/material.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'screens.dart';

Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)));
Widget _field(String label,
        {String? value, String? hint, int lines = 1, IconData? icon}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(label),
      TextFormField(
          initialValue: value,
          maxLines: lines,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
              hintText: hint,
              suffixIcon: icon == null ? null : Icon(icon, size: 16),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 13)))
    ]);
Widget _select(String label, List<String> items, {String? value}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _label(label),
      DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          style: const TextStyle(
              fontFamily: 'Roboto', color: Emville.ink, fontSize: 12),
          hint: Text('Select bill type',
              style: const TextStyle(fontSize: 12, color: Emville.muted)),
          decoration: const InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 13, vertical: 13)),
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(item))
          ],
          onChanged: (_) {})
    ]);
Widget _date(String title, String value) =>
    _field(title, value: value, icon: Icons.calendar_today_outlined);

class AddBillDesignConcept extends StatelessWidget {
  const AddBillDesignConcept({super.key});
  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 1,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('BOOKINGS / BILLING',
                style: TextStyle(fontSize: 9, letterSpacing: 1.6)),
            const SizedBox(height: 12),
            Text('Add bill', style: Emville.heading(31)),
            const SizedBox(height: 7),
            const Text('Every extra, clearly accounted for.',
                style: TextStyle(fontSize: 11, color: Emville.muted)),
            const SizedBox(height: 22),
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: Emville.sage,
                    borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.person_outline, size: 19),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Tribenee chetry', style: Emville.heading(20)),
                        const SizedBox(height: 5),
                        const Text('12–13 Dec 2026 · 7 guests',
                            style:
                                TextStyle(fontSize: 10, color: Emville.muted))
                      ])),
                  const Icon(Icons.lock_outline, size: 14, color: Emville.muted)
                ])),
            const SizedBox(height: 23),
            Text('Bill details', style: Emville.heading(23)),
            const SizedBox(height: 15),
            Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: Emville.paper,
                    border: Border.all(color: Emville.line),
                    borderRadius: BorderRadius.circular(13)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _date('Date', '12 Dec 2026'),
                      const SizedBox(height: 18),
                      _select('Bill type', ['Food & beverage', 'Other']),
                      const SizedBox(height: 18),
                      _field('Bill amount (INR)', hint: '0.00'),
                      const SizedBox(height: 18),
                      _field('Remarks', hint: 'e.g. Dinner · 500', lines: 3),
                    ])),
            const SizedBox(height: 14),
            const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.info_outline, size: 14, color: Emville.muted),
              SizedBox(width: 8),
              Expanded(
                  child: Text('This bill will be added to this guest’s stay.',
                      style: TextStyle(
                          fontSize: 10, height: 1.5, color: Emville.muted)))
            ]),
            const Spacer(),
            FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add, size: 17),
                label: const Text('Add bill')),
            const SizedBox(height: 6),
          ])));
}

class FinaliseBillDesignConcept extends StatefulWidget {
  const FinaliseBillDesignConcept({super.key});
  @override
  State<FinaliseBillDesignConcept> createState() =>
      _FinaliseBillDesignConceptState();
}

class _FinaliseBillDesignConceptState extends State<FinaliseBillDesignConcept> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showDialog<void>(
            context: context,
            barrierColor: const Color(0x85203E34),
            builder: (_) => const _FinaliseDialogConcept());
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      const BookingDesignConcept(billing: true);
}

class _FinaliseDialogConcept extends StatelessWidget {
  const _FinaliseDialogConcept();
  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      backgroundColor: Emville.ivory,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 390),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
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
                    const Text('Tribenee chetry · Review payment details',
                        style: TextStyle(fontSize: 10, color: Emville.muted)),
                    const SizedBox(height: 22),
                    Text('Discounts', style: Emville.heading(21)),
                    const SizedBox(height: 12),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _field('F&B (%)', value: '0')),
                          const SizedBox(width: 12),
                          Expanded(child: _field('Other (%)', value: '0'))
                        ]),
                    const SizedBox(height: 13),
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Emville.sage,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Row(children: [
                          Expanded(
                              child: Text('After discounts',
                                  style: TextStyle(
                                      fontSize: 10, color: Emville.muted))),
                          Text('F&B ₹0  ·  Other ₹0',
                              style: TextStyle(fontSize: 10))
                        ])),
                    const SizedBox(height: 22),
                    Text('Payment', style: Emville.heading(21)),
                    const SizedBox(height: 13),
                    _date('Check-in date', '12 Dec 2026'),
                    const SizedBox(height: 12),
                    _date('Check-out date', '13 Dec 2026'),
                    const SizedBox(height: 12),
                    _date('Payment date', '13 Dec 2026'),
                    const SizedBox(height: 12),
                    _field('Payee name', hint: 'Enter payee name'),
                    const SizedBox(height: 12),
                    _select('Payment type',
                        ['Cash', 'UPI', 'Card', 'Bank Transfer'],
                        value: 'Cash'),
                    const SizedBox(height: 19),
                    const Text(
                        'Continue to review the final bill before saving.',
                        style: TextStyle(
                            fontSize: 10, height: 1.5, color: Emville.muted)),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'))),
                      const SizedBox(width: 10),
                      Expanded(
                          child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Continue')))
                    ]),
                  ]))));
}
