import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_widgets.dart';
import 'report_ledger_page.dart';
import 'report_income_page.dart';
import 'report_expenses_page.dart';
import 'report_pl_page.dart';
import 'report_petty_cash_page.dart';
import 'advanced_filter_page.dart';
import 'package:emville_pms/features/pms/generate_pms_report.dart';

class GenerateReportsPage extends StatefulWidget {
  const GenerateReportsPage({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<GenerateReportsPage> createState() => _GenerateReportsPageState();
}

class _GenerateReportsPageState extends State<GenerateReportsPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<double>> _trend;
  @override
  void initState() {
    super.initState();
    _trend = _load();
  }

  Future<List<double>> _load() async {
    final start = DateTime(_month.year, _month.month - 5);
    final end = DateTime(_month.year, _month.month + 1);
    final rows = await Supabase.instance.client
        .from('main_ledger')
        .select('date,amount')
        .eq('transaction_type', 'income')
        .eq('transaction_status', 'approved')
        .gte('date', DateFormat('yyyy-MM-dd').format(start))
        .lt('date', DateFormat('yyyy-MM-dd').format(end));
    final totals = List<double>.filled(6, 0);
    for (final row in rows) {
      final date = DateTime.tryParse(row['date']?.toString() ?? '');
      if (date == null) continue;
      final index = (date.year - start.year) * 12 + date.month - start.month;
      if (index >= 0 && index < 6) {
        totals[index] += (row['amount'] as num?)?.toDouble() ?? 0;
      }
    }
    return totals;
  }

  void _reload() => setState(() {
        _trend = _load();
      });
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final body = EmvilleBody(
        child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 22),
            children: [
          const EmvilleHeading('Reports',
              eyebrow: 'Insight into your property',
              subtitle: 'From daily details to the bigger picture.'),
          const SizedBox(height: 18),
          DropdownButtonFormField<DateTime>(
              key: const ValueKey('report-period'),
              initialValue: _month,
              isExpanded: true,
              style: const TextStyle(
                  fontFamily: 'Roboto', fontSize: 11, color: Emville.ink),
              decoration: const InputDecoration(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  isDense: true),
              items: List.generate(12, (i) => DateTime(now.year, now.month - i))
                  .map((d) => DropdownMenuItem(
                      value: d, child: Text(DateFormat('MMMM yyyy').format(d))))
                  .toList(),
              onChanged: (d) {
                if (d != null) {
                  _month = d;
                  _reload();
                }
              }),
          const EmvilleSectionTitle('Income trend',
              trailing: Text('₹ thousands',
                  style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 10,
                      color: Emville.muted))),
          FutureBuilder<List<double>>(
              future: _trend,
              builder: (context, snapshot) {
                if (snapshot.hasError) return EmvilleError(onRetry: _reload);
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!snapshot.hasData)
                        const SizedBox(
                            height: 98,
                            child: Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))))
                      else
                        IncomeTrend(values: snapshot.data!, endMonth: _month),
                      const SizedBox(height: 9),
                      Text(
                          snapshot.hasData &&
                                  snapshot.data!.every((v) => v == 0)
                              ? 'No approved income recorded for these months.'
                              : 'Income trend · approved entries',
                          style: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 10,
                              color: Emville.muted)),
                    ]);
              }),
          const SizedBox(height: 18),
          GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              mainAxisExtent: 111,
              children: [
                for (final report in <(String, String, Widget)>[
                  (
                    'Main ledger',
                    'Opening & closing balances',
                    const ReportLedgerPage()
                  ),
                  ('Income', 'Receipts by period', const ReportIncomePage()),
                  (
                    'Expenses',
                    'Where the money goes',
                    const ReportExpensesPage()
                  ),
                  (
                    'Profit & loss',
                    'Income less expenses',
                    const ReportPlPage()
                  ),
                  (
                    'Petty cash',
                    'Bills, top-ups & balances',
                    const ReportPettyCashPage()
                  ),
                  (
                    'Maintenance',
                    'Planned & completed work',
                    const GeneratePmsReportPage()
                  ),
                ])
                  Material(
                      color: const Color(0xFFFFFDF7),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Emville.line)),
                      child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => report.$3)),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.north_east, size: 15),
                                    const SizedBox(height: 9),
                                    Text(report.$1, style: Emville.heading(16)),
                                    const SizedBox(height: 5),
                                    Text(report.$2,
                                        style: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 10,
                                            color: Emville.muted,
                                            height: 1.3))
                                  ])))),
              ]),
          const SizedBox(height: 18),
          const EmvilleCallout(
              child: Text(
                  'Choose a report to set its dates,\nreview the detail and export.')),
          Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AdvancedFilterPage())),
                  child: const Text('Advanced filters',
                      style: TextStyle(fontFamily: 'Roboto', fontSize: 11)))),
        ]));
    return widget.embedded ? body : EmvillePage(section: 2, child: body);
  }
}

class IncomeTrend extends StatelessWidget {
  const IncomeTrend({super.key, required this.values, required this.endMonth});
  final List<double> values;
  final DateTime endMonth;
  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<double>(0, math.max);
    return Column(children: [
      Container(
          height: 90,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Emville.line))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final item in values.indexed)
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Semantics(
                          label:
                              '${DateFormat('MMMM').format(DateTime(endMonth.year, endMonth.month - 5 + item.$1))}: ${rupees(item.$2)}',
                          child: Container(
                              height:
                                  maximum == 0 ? 0 : (item.$2 / maximum * 80),
                              decoration: BoxDecoration(
                                  color: item.$1 == 5
                                      ? const Color(0xFF315E47)
                                      : const Color(0xFFAEBDA6),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(3))))))),
          ])),
      const SizedBox(height: 8),
      Row(children: [
        for (var i = 0; i < 6; i++)
          Expanded(
              child: Text(
                  DateFormat('MMM')
                      .format(DateTime(endMonth.year, endMonth.month - 5 + i)),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'Roboto', fontSize: 9, color: Emville.muted)))
      ]),
    ]);
  }
}
