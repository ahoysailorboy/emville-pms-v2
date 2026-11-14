import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'emville_theme.dart';

String rupees(num value) => NumberFormat.currency(
        locale: 'en_IN',
        symbol: '₹',
        decimalDigits: value == value.roundToDouble() ? 0 : 2)
    .format(value);
String shortDate(String date) {
  final d = DateTime.tryParse(date);
  return d == null ? date : DateFormat('d MMM').format(d);
}

/// The compact heading hierarchy used by the approved phone concepts.
class EmvilleHeading extends StatelessWidget {
  const EmvilleHeading(this.title, {super.key, this.eyebrow, this.subtitle});
  final String title;
  final String? eyebrow, subtitle;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (eyebrow != null)
          Text(eyebrow!.toUpperCase(),
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 10,
                  letterSpacing: 2,
                  height: 1.3)),
        const SizedBox(height: 12),
        Text(title, style: Emville.heading(30)),
        if (subtitle != null) ...[
          const SizedBox(height: 7),
          Text(subtitle!,
              style: const TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 12,
                  color: Emville.muted,
                  height: 1.6))
        ],
      ]);
}

class EmvilleTile extends StatelessWidget {
  const EmvilleTile(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap,
      this.trailing});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 17),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Emville.line))),
        child: Row(children: [
          Container(
              width: 39,
              height: 39,
              decoration: BoxDecoration(
                  color: Emville.sage, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, size: 18, color: Emville.forest)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.3)),
                const SizedBox(height: 5),
                Text(subtitle,
                    style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 10,
                        color: Emville.muted,
                        height: 1.5)),
              ])),
          const SizedBox(width: 8),
          trailing ?? const Icon(Icons.arrow_forward, size: 17),
        ]),
      ));
}

class EmvilleBalance extends StatelessWidget {
  const EmvilleBalance(
      {super.key,
      required this.label,
      required this.amount,
      this.details = const {}});
  final String label, amount;
  final Map<String, String> details;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: Emville.forest, borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                fontFamily: 'Roboto',
                color: Color(0xFFD7DFCB),
                fontSize: 9,
                letterSpacing: 1.6,
                height: 1.4)),
        const SizedBox(height: 13),
        Text(amount, style: Emville.heading(36).copyWith(color: Emville.paper)),
        if (details.isNotEmpty) ...[
          const SizedBox(height: 17),
          const Divider(height: 1, color: Color(0x24FFFFFF)),
          const SizedBox(height: 16),
          Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details.entries
                  .map((e) => Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(e.key,
                                style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    color: Color(0xFFD7DFCB),
                                    fontSize: 10,
                                    height: 1.4)),
                            const SizedBox(height: 6),
                            Text(e.value,
                                style: const TextStyle(
                                    fontFamily: 'Roboto',
                                    color: Emville.paper,
                                    fontSize: 15,
                                    height: 1.3)),
                          ])))
                  .toList()),
        ],
      ]));
}

class EmvilleSectionTitle extends StatelessWidget {
  const EmvilleSectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Row(children: [
        Expanded(child: Text(title, style: Emville.heading(20))),
        if (trailing != null) trailing!
      ]));
}

class EmvilleTabs extends StatelessWidget {
  const EmvilleTabs(
      {super.key,
      required this.labels,
      required this.selected,
      required this.onSelected});
  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
          color: const Color(0xFFEEEEE5),
          borderRadius: BorderRadius.circular(10)),
      child: Row(
          children: labels
              .map((label) => Expanded(
                  child: Semantics(
                      selected: selected == label,
                      button: true,
                      child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: () => onSelected(label),
                          child: Container(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 11, horizontal: 4),
                              decoration: BoxDecoration(
                                  color: selected == label
                                      ? const Color(0xFFFFFDF6)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7)),
                              child: Text(label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 10,
                                      color: selected == label
                                          ? Emville.ink
                                          : Emville.muted)))))))
              .toList()));
}

class EmvilleTag extends StatelessWidget {
  const EmvilleTag(this.label,
      {super.key, this.warning = false, this.overdue = false});
  final String label;
  final bool warning, overdue;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      decoration: BoxDecoration(
          color: overdue
              ? const Color(0xFFF3E2DA)
              : warning
                  ? const Color(0xFFF3E8D2)
                  : Emville.sage,
          borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 9,
              height: 1.1,
              color: overdue
                  ? const Color(0xFF9C513C)
                  : warning
                      ? const Color(0xFF8A642E)
                      : Emville.forest)));
}

class EmvilleCallout extends StatelessWidget {
  const EmvilleCallout(
      {super.key,
      required this.child,
      this.leading,
      this.trailing,
      this.onTap});
  final Widget child;
  final Widget? leading, trailing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
              color: const Color(0xFFEFEBDC).withValues(alpha: 1),
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
                child: DefaultTextStyle.merge(
                    style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 11,
                        color: Emville.ink,
                        height: 1.5),
                    child: child)),
            if (trailing != null) trailing!
          ])));
}

class EmvilleError extends StatelessWidget {
  const EmvilleError(
      {super.key,
      required this.onRetry,
      this.message = 'Could not load this information.'});
  final VoidCallback onRetry;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.cloud_off_outlined, color: Emville.muted),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Roboto', fontSize: 12)),
        TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'))
      ]));
}

class EmvilleBody extends StatelessWidget {
  const EmvilleBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720), child: child));
}

class EmvilleNavigation {
  static final section = ValueNotifier<int>(0);
  static String initials = 'EM';
  static VoidCallback? drawerOpener;
  static void openMenu(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    WidgetsBinding.instance.addPostFrameCallback((_) => drawerOpener?.call());
  }

  static void go(BuildContext context, int index) {
    Navigator.of(context).popUntil((route) => route.isFirst);
    section.value = index;
  }
}

class EmvilleBottomNav extends StatelessWidget {
  const EmvilleBottomNav(
      {super.key, required this.selectedIndex, this.onSelected});
  final int selectedIndex;
  final ValueChanged<int>? onSelected;
  @override
  Widget build(BuildContext context) => Container(
      decoration: const BoxDecoration(
          color: Emville.ivory,
          border: Border(top: BorderSide(color: Emville.line))),
      child: SafeArea(
          top: false,
          child: Padding(
              padding: EdgeInsets.fromLTRB(12, selectedIndex == 0 ? 2 : 4, 12,
                  selectedIndex == 0 ? 2 : 7),
              child: Row(children: [
                for (final item in <(IconData, String)>[
                  (Icons.home_outlined, 'Home'),
                  (Icons.event_available_outlined, 'Bookings'),
                  (Icons.account_balance_wallet_outlined, 'Accounts'),
                  (Icons.home_work_outlined, 'Property')
                ].indexed)
                  Expanded(
                      child: Semantics(
                          selected: item.$1 == selectedIndex,
                          button: true,
                          child: InkWell(
                              onTap: () => (onSelected ??
                                      (i) => EmvilleNavigation.go(context, i))(
                                  item.$1),
                              child: Padding(
                                  padding: EdgeInsets.symmetric(
                                      vertical: selectedIndex == 0 ? 6 : 10),
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(item.$2.$1,
                                            size: selectedIndex == 0 ? 16 : 19,
                                            color: item.$1 == selectedIndex
                                                ? Emville.forest
                                                : Emville.muted),
                                        SizedBox(
                                            height: selectedIndex == 0 ? 4 : 6),
                                        Text(item.$2.$2,
                                            style: TextStyle(
                                                fontFamily: 'Roboto',
                                                fontSize: 10,
                                                color: item.$1 == selectedIndex
                                                    ? Emville.forest
                                                    : Emville.muted,
                                                fontWeight:
                                                    item.$1 == selectedIndex
                                                        ? FontWeight.w600
                                                        : FontWeight.w400))
                                      ]))))),
              ]))));
}

class EmvilleHeader extends StatelessWidget {
  const EmvilleHeader(
      {super.key,
      this.onMenu,
      this.initials,
      this.back = false,
      this.home = false});
  final VoidCallback? onMenu;
  final String? initials;
  final bool back, home;
  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
        radius: 17,
        backgroundColor: const Color(0xFFE4E9DD),
        child: Text(initials ?? EmvilleNavigation.initials,
            style: const TextStyle(
                fontFamily: 'Roboto', fontSize: 11, color: Emville.ink)));
    final logo = Image.asset(Emville.logo,
        width: home ? 115 : 100, height: home ? 60 : 51, fit: BoxFit.contain);
    return EmvilleBody(
        child: Padding(
            padding: EdgeInsets.fromLTRB(22, home ? 4 : 2, 22, home ? 6 : 10),
            child: SizedBox(
                height: home ? 60 : 51,
                child: Row(children: [
                  IconButton(
                    tooltip: back ? 'Back' : 'Open menu',
                    onPressed: back
                        ? () => Navigator.of(context).maybePop()
                        : onMenu ?? () => EmvilleNavigation.openMenu(context),
                    padding: EdgeInsets.zero,
                    icon: Icon(back ? Icons.arrow_back : Icons.menu,
                        size: 23, color: Emville.ink),
                  ),
                  Expanded(child: Center(child: logo)),
                  SizedBox(width: 48, child: Center(child: avatar)),
                ]))));
  }
}

class EmvillePage extends StatelessWidget {
  const EmvillePage({super.key, required this.child, this.section = 2});
  final Widget child;
  final int section;
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          bottom: false,
          child: Column(children: [
            const RepaintBoundary(child: EmvilleHeader(back: true)),
            Expanded(child: child)
          ])),
      bottomNavigationBar: EmvilleBottomNav(selectedIndex: section));
}
