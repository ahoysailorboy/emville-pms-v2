import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
export 'package:emville_pms/ui/emville_theme.dart';
export 'package:emville_pms/ui/emville_widgets.dart';

DateTime? bookingDate(dynamic value) => value is DateTime
    ? value.toLocal()
    : DateTime.tryParse('$value')?.toLocal();
num? bookingNumber(dynamic value) =>
    value is num ? value : num.tryParse('$value');
String bookingMoney(dynamic value, String? currency) {
  final amount = bookingNumber(value);
  if (amount == null) return '—';
  final code = currency?.trim().isNotEmpty == true ? currency!.trim() : 'INR';
  return NumberFormat.currency(
          locale: code == 'INR' ? 'en_IN' : 'en',
          symbol: code == 'INR' ? '₹' : '$code ',
          decimalDigits: amount == amount.roundToDouble() ? 0 : 2)
      .format(amount);
}

class BookingFrame extends StatelessWidget {
  const BookingFrame(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.children,
      this.actions,
      this.eyebrow = 'Bookings / Guest stay'});
  final String title, subtitle, eyebrow;
  final List<Widget> children;
  final Widget? actions;
  @override
  Widget build(BuildContext context) => EmvillePage(
      section: 1,
      child: EmvilleBody(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                children: [
              EmvilleHeading(title, eyebrow: eyebrow, subtitle: subtitle),
              const SizedBox(height: 22),
              ...children
            ])),
        if (actions != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
              child: actions!)
      ])));
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Emville.paper,
          border: Border.all(color: Emville.line),
          borderRadius: BorderRadius.circular(13)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
}

class BookingValue extends StatelessWidget {
  const BookingValue(this.label, this.value, {super.key, this.strong = false});
  final String label, value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Emville.muted))),
        const SizedBox(width: 12),
        Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: strong ? FontWeight.w600 : FontWeight.w400)))
      ]));
}

Widget bookingSection(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 13),
    child: Text(title, style: Emville.heading(22)));
Widget bookingLabel(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Text(title,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)));
InputDecoration bookingDecoration({String? hint, Widget? suffix}) =>
    InputDecoration(
        hintText: hint,
        suffixIcon: suffix,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 13));

class BookingBalance extends StatelessWidget {
  const BookingBalance(
      {super.key,
      required this.amount,
      required this.currency,
      required this.detail});
  final num amount;
  final String currency, detail;
  @override
  Widget build(BuildContext context) => ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
          decoration: const BoxDecoration(
              image: DecorationImage(
                  image: AssetImage(Emville.pool), fit: BoxFit.cover)),
          child: Container(
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Color(0xED113D32), Color(0xB3113D32)])),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('BALANCE TO BE PAID · $currency',
                        style: const TextStyle(
                            color: Color(0xFFD7DFCB),
                            fontSize: 9,
                            letterSpacing: 1.4)),
                    const SizedBox(height: 10),
                    Text(bookingMoney(amount, currency),
                        style:
                            Emville.heading(34).copyWith(color: Emville.paper)),
                    const SizedBox(height: 10),
                    Text(detail,
                        style: const TextStyle(
                            color: Emville.paper, fontSize: 10, height: 1.5))
                  ]))));
}
