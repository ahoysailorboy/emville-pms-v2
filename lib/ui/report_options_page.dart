import 'package:flutter/material.dart';
import 'emville_theme.dart';
import 'emville_widgets.dart';

/// Shared presentation only; each report retains its own range/query/export logic.
class ReportOptionsPage extends StatefulWidget {
  const ReportOptionsPage(
      {super.key,
      required this.title,
      required this.period,
      required this.periodLabels,
      required this.onPeriod,
      required this.dateSelection,
      required this.status,
      required this.onStatus,
      required this.format,
      required this.onFormat,
      required this.rangeSummary,
      required this.onGenerate});
  final String title, period, status, format, rangeSummary;
  final Map<String, String> periodLabels;
  final ValueChanged<String> onPeriod, onStatus, onFormat;
  final Widget dateSelection;
  final Future<void> Function() onGenerate;
  @override
  State<ReportOptionsPage> createState() => _ReportOptionsPageState();
}

class _ReportOptionsPageState extends State<ReportOptionsPage> {
  bool _busy = false;
  Future<void> _generate() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onGenerate();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to generate the report. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _choices(String value, Map<String, String> labels,
          ValueChanged<String> onChanged) =>
      SegmentedButton<String>(
        showSelectedIcon: false,
        expandedInsets: EdgeInsets.zero,
        style: ButtonStyle(
          textStyle: const WidgetStatePropertyAll(TextStyle(
              fontFamily: 'Roboto', fontSize: 11, fontWeight: FontWeight.w500)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          padding:
              const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)),
          side: const WidgetStatePropertyAll(BorderSide(color: Emville.line)),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? Emville.forest
                  : Emville.paper),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? Emville.paper
                  : Emville.ink),
        ),
        segments: [
          for (final item in labels.entries)
            ButtonSegment(value: item.key, label: Text(item.value))
        ],
        selected: {value},
        onSelectionChanged: _busy ? null : (v) => onChanged(v.first),
      );
  Widget _card(String title, Widget child) => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Emville.paper,
          border: Border.all(color: Emville.line),
          borderRadius: BorderRadius.circular(13)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: Emville.heading(22)),
        const SizedBox(height: 16),
        child
      ]));
  @override
  Widget build(BuildContext context) => EmvillePage(
          child: EmvilleBody(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            Expanded(
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                    children: [
                  EmvilleHeading(widget.title,
                      eyebrow: 'Accounts / Reports',
                      subtitle: 'Choose a period, status and export format.'),
                  const SizedBox(height: 22),
                  AbsorbPointer(
                      absorbing: _busy,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _card(
                                'Report range',
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _choices(widget.period,
                                          widget.periodLabels, widget.onPeriod),
                                      const SizedBox(height: 18),
                                      widget.dateSelection
                                    ])),
                            const SizedBox(height: 14),
                            _card(
                                'Transaction status',
                                _choices(
                                    widget.status,
                                    const {
                                      'approved': 'Approved',
                                      'pending': 'Pending',
                                      'all': 'All'
                                    },
                                    widget.onStatus)),
                            const SizedBox(height: 14),
                            _card(
                                'File type',
                                Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _choices(
                                          widget.format,
                                          const {
                                            'excel': 'Excel',
                                            'pdf': 'PDF'
                                          },
                                          widget.onFormat),
                                      const SizedBox(height: 12),
                                      Text(
                                          widget.format == 'pdf'
                                              ? 'A print-ready report with the Emville letterhead.'
                                              : 'A spreadsheet for sorting and further analysis.',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              height: 1.5,
                                              color: Emville.muted))
                                    ])),
                            const SizedBox(height: 16),
                            Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                    color: Emville.sage,
                                    borderRadius: BorderRadius.circular(11)),
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.description_outlined,
                                          size: 18, color: Emville.forest),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(
                                              '${widget.rangeSummary}\n${widget.status == 'all' ? 'All transactions' : '${widget.status[0].toUpperCase()}${widget.status.substring(1)} transactions'} · ${widget.format == 'pdf' ? 'PDF' : 'Excel'}',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  height: 1.7,
                                                  color: Emville.ink)))
                                    ])),
                          ])),
                ])),
            Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
                child: FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(_busy ? 'Generating…' : 'Generate report'))),
          ])));
}

Widget reportDateField(String label, String value, VoidCallback onTap) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: const TextStyle(fontSize: 10, color: Emville.muted)),
      const SizedBox(height: 8),
      InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  border: Border.all(color: Emville.line),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(
                    child: Text(value,
                        style:
                            const TextStyle(fontSize: 12, color: Emville.ink))),
                const SizedBox(width: 4),
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: Emville.forest)
              ])))
    ]);
Widget reportYearField(
        int year, int defaultYear, ValueChanged<int> onChanged) =>
    DropdownButtonFormField<int>(
        initialValue: year,
        isExpanded: true,
        decoration: const InputDecoration(
            labelText: 'Financial year',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
        style: const TextStyle(
            fontFamily: 'Roboto', fontSize: 12, color: Emville.ink),
        items: [
          for (var y = defaultYear - 6; y < defaultYear + 6; y++)
            DropdownMenuItem(value: y, child: Text('$y–${y + 1}'))
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        });
