import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'emville_theme.dart';

class EmvilleCalendar extends StatelessWidget {
  const EmvilleCalendar(
      {super.key,
      required this.month,
      required this.selectedDay,
      required this.activity,
      required this.onSelected,
      required this.onPrevious,
      required this.onNext,
      this.loading = false});
  final DateTime month, selectedDay;
  final Set<DateTime> activity;
  final ValueChanged<DateTime> onSelected;
  final VoidCallback onPrevious, onNext;
  final bool loading;
  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final offset = first.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final cells = ((offset + count) / 7).ceil() * 7;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
        decoration: BoxDecoration(
            color: Emville.paper,
            border: Border.all(color: const Color(0xFFE5E6DD)),
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(DateFormat('MMMM yyyy').format(month),
                    style: Emville.heading(21))),
            IconButton(
                tooltip: 'Previous month',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left, size: 20)),
            IconButton(
                tooltip: 'Next month',
                constraints: const BoxConstraints(minWidth: 32, minHeight: 26),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right, size: 20))
          ]),
          const SizedBox(height: 16),
          Row(children: [
            for (final day in ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])
              Expanded(
                  child: Text(day,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: 9,
                          color: Emville.muted)))
          ]),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
                height: 2, child: LinearProgressIndicator(minHeight: 2)),
          GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7, mainAxisExtent: 30),
              itemBuilder: (context, i) {
                final day = DateTime(month.year, month.month, i - offset + 1);
                final inMonth = day.month == month.month;
                final selected = DateUtils.isSameDay(day, selectedDay);
                return Semantics(
                    label: DateFormat('EEEE, d MMMM yyyy').format(day),
                    selected: selected,
                    button: true,
                    child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: inMonth ? () => onSelected(day) : null,
                        child: Container(
                            decoration: BoxDecoration(
                                color: selected && inMonth
                                    ? Emville.forest
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8)),
                            child:
                                Stack(alignment: Alignment.center, children: [
                              Text(inMonth ? '${day.day}' : '',
                                  style: TextStyle(
                                      fontFamily: 'Roboto',
                                      fontSize: 11,
                                      color: selected && inMonth
                                          ? Colors.white
                                          : inMonth
                                              ? Emville.ink
                                              : const Color(0xFFB5BAB0))),
                              if (inMonth && activity.contains(day))
                                Positioned(
                                    bottom: 3,
                                    child: Container(
                                        width: 4,
                                        height: 4,
                                        decoration: BoxDecoration(
                                            color: selected
                                                ? Emville.paper
                                                : Emville.gold,
                                            shape: BoxShape.circle)))
                            ]))));
              }),
          const SizedBox(height: 12),
          const Row(children: [
            Icon(Icons.circle, size: 5, color: Emville.gold),
            SizedBox(width: 5),
            Text('Booking activity',
                style: TextStyle(
                    fontFamily: 'Roboto', fontSize: 9, color: Emville.muted)),
            SizedBox(width: 15),
            Icon(Icons.circle, size: 5, color: Emville.forest),
            SizedBox(width: 5),
            Flexible(
                child: Text('Selected day highlighted',
                    style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 9,
                        color: Emville.muted)))
          ]),
        ]));
  }
}
