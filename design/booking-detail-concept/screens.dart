// Design-only fixture screens. No backend access or financial mutations.
import 'package:flutter/material.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';

class BookingDesignConcept extends StatelessWidget {
  const BookingDesignConcept({super.key, this.billing = false});
  final bool billing;
  Widget label(String text) => Text(text.toUpperCase(),
      style: const TextStyle(
          fontSize: 9, letterSpacing: 1.4, color: Emville.muted));
  Widget row(String title, String value, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(fontSize: 11, color: Emville.muted))),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400))
      ]));
  Widget card(List<Widget> children) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Emville.paper,
          border: Border.all(color: Emville.line),
          borderRadius: BorderRadius.circular(13)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  Widget dates() => Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label('Check-in'),
          const SizedBox(height: 8),
          Text('12 Dec 2026', style: Emville.heading(19)),
          const SizedBox(height: 5),
          const Text('Saturday · 12:00 AM',
              style: TextStyle(fontSize: 10, color: Emville.muted))
        ])),
        const Icon(Icons.arrow_forward, size: 17, color: Emville.muted),
        const SizedBox(width: 22),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          label('Check-out'),
          const SizedBox(height: 8),
          Text('13 Dec 2026', style: Emville.heading(19)),
          const SizedBox(height: 5),
          const Text('Sunday · 12:00 AM',
              style: TextStyle(fontSize: 10, color: Emville.muted))
        ]))
      ]);
  Widget balance() => Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          image: const DecorationImage(
              image: AssetImage(Emville.pool), fit: BoxFit.cover)),
      child: Container(
          decoration: BoxDecoration(
              color: Emville.forest.withValues(alpha: .90),
              borderRadius: BorderRadius.circular(9)),
          padding: const EdgeInsets.all(15),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('BALANCE TO BE PAID · INR',
                style: TextStyle(
                    color: Color(0xFFD7DFCB), fontSize: 9, letterSpacing: 1.4)),
            const SizedBox(height: 9),
            Text('₹11,500',
                style: Emville.heading(34).copyWith(color: Emville.paper)),
            const SizedBox(height: 8),
            const Text('Room rent ₹23,000  ·  Advance paid ₹11,500',
                style: TextStyle(color: Emville.paper, fontSize: 10))
          ])));
  Widget empty(String title, String subtitle, IconData icon) => card([
        Row(children: [
          Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: Emville.sage, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 17)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Emville.heading(19)),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: const TextStyle(fontSize: 10, color: Emville.muted))
              ])),
          const Text('₹0', style: TextStyle(fontSize: 15))
        ]),
        const SizedBox(height: 15),
        const Divider(height: 1),
        const SizedBox(height: 12),
        const Text('No items added yet.',
            style: TextStyle(fontSize: 11, color: Emville.muted))
      ]);
  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 1,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('BOOKINGS / GUEST STAY',
                style: TextStyle(fontSize: 9, letterSpacing: 1.6)),
            const SizedBox(height: 12),
            Text(billing ? 'Billing' : 'Booking details',
                style: Emville.heading(31)),
            const SizedBox(height: 7),
            Text(
                billing
                    ? 'Tribenee chetry · 12–13 Dec 2026'
                    : 'A thoughtful stay, with every detail in place.',
                style: const TextStyle(fontSize: 11, color: Emville.muted)),
            const SizedBox(height: 22),
            if (!billing) ...[
              card([
                Row(children: [
                  const Expanded(
                      child: Text('GUEST & STATUS',
                          style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.4,
                              color: Emville.muted))),
                  const EmvilleTag('Confirmed')
                ]),
                const SizedBox(height: 14),
                Text('Tribenee chetry', style: Emville.heading(26)),
                const SizedBox(height: 14),
                Row(children: [
                  const Icon(Icons.people_alt_outlined, size: 16),
                  const SizedBox(width: 7),
                  const Text('7 guests', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 20),
                  const Icon(Icons.travel_explore, size: 16),
                  const SizedBox(width: 7),
                  const Text('Other', style: TextStyle(fontSize: 11))
                ])
              ]),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(child: Text('The stay', style: Emville.heading(22))),
                const EmvilleTag('1 night')
              ]),
              const SizedBox(height: 13),
              card([dates()]),
              const SizedBox(height: 20),
              Text('Payment summary', style: Emville.heading(22)),
              const SizedBox(height: 13),
              card([
                row('Currency', 'INR'),
                row('Total price', '₹23,000'),
                row('Advance paid', '₹11,500'),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Divider(height: 1)),
                row('Balance to be paid', '₹11,500', strong: true)
              ]),
              const SizedBox(height: 20),
              Text('Notes', style: Emville.heading(22)),
              const SizedBox(height: 10),
              card([
                const Text('No notes added.',
                    style: TextStyle(fontSize: 11, color: Emville.muted))
              ]),
            ] else ...[
              balance(),
              const SizedBox(height: 20),
              Text('Accommodation', style: Emville.heading(22)),
              const SizedBox(height: 13),
              card([
                row('Room rent', '₹23,000'),
                row('Advance paid', '− ₹11,500'),
                row('Booking source', 'Other')
              ]),
              const SizedBox(height: 18),
              empty('Food & beverage', 'Meals, drinks and dining',
                  Icons.restaurant_outlined),
              const SizedBox(height: 13),
              empty('Miscellaneous', 'Other charges for this stay',
                  Icons.receipt_long_outlined),
              const SizedBox(height: 16),
              const Text(
                  'All amounts in INR. Review charges before finalising.',
                  style: TextStyle(
                      fontSize: 10, height: 1.5, color: Emville.muted)),
            ],
            const Spacer(),
            const SizedBox(height: 15),
            if (billing)
              Row(children: [
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add bill'))),
                const SizedBox(width: 10),
                Expanded(
                    child: FilledButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Finalise bill')))
              ])
            else
              FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.receipt_long_outlined, size: 17),
                  label: const Text('View billing')),
          ])));
}
