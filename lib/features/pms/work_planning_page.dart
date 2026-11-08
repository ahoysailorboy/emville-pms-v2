// lib/features/pms/work_planning_page.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive helper
import 'package:emville_pms/responsive/responsive.dart';

/// Work Planning page (Weekly / Monthly / Custom) → PDF "Work Planner"
class WorkPlanningPage extends StatefulWidget {
  const WorkPlanningPage({super.key});

  @override
  State<WorkPlanningPage> createState() => _WorkPlanningPageState();
}

enum _PlanMode { weekly, monthly, custom }

class _WorkPlanningPageState extends State<WorkPlanningPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  _PlanMode _mode = _PlanMode.monthly;

  // Range state
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  // Monthly picker (month anchor)
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  final _dfSql = DateFormat('yyyy-MM-dd');
  final _dfUi = DateFormat('dd MMM yyyy');

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  void _initDefaults() {
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _to = _lastDayOfNextMonth(now);
    _month = DateTime(now.year, now.month, 1);
    setState(() {});
  }

  // ---------- Date helpers & validation ----------
  DateTime _startOfWeek(DateTime d) {
    // ISO: Mon=1..Sun=7 → week Mon..Sun
    final wd = d.weekday; // 1..7
    return DateTime(d.year, d.month, d.day).subtract(Duration(days: wd - 1));
  }

  DateTime _endOfWeek(DateTime d) {
    final start = _startOfWeek(d);
    return start.add(const Duration(days: 6));
  }

  DateTime _lastDayOfMonth(DateTime d) =>
      DateTime(d.year, d.month + 1, 0); // day 0 of next month = last of this

  DateTime _lastDayOfNextMonth(DateTime base) {
    final nextMonth = DateTime(base.year, base.month + 1, 1);
    return _lastDayOfMonth(nextMonth);
  }

  DateTime get _minDate =>
      DateTime.now(); // cannot select before current date/week/month
  DateTime get _maxDate => _lastDayOfNextMonth(DateTime.now());

  // Clamp custom/weekly range to [today .. end of next month]
  void _clampFromTo() {
    if (_from.isBefore(_minDate)) _from = _minDate;
    if (_to.isBefore(_minDate)) _to = _minDate;
    if (_from.isAfter(_maxDate)) _from = _maxDate;
    if (_to.isAfter(_maxDate)) _to = _maxDate;
    if (_from.isAfter(_to)) _to = _from;
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from.isBefore(_minDate) ? _minDate : _from,
      firstDate: _minDate,
      lastDate: _maxDate,
      helpText: 'From date',
    );
    if (picked != null) {
      if (_mode == _PlanMode.weekly) {
        _from = _startOfWeek(picked);
        _to = _endOfWeek(picked);
      } else {
        _from = DateTime(picked.year, picked.month, picked.day);
      }
      _clampFromTo();
      setState(() {});
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to.isAfter(_maxDate) ? _maxDate : _to,
      firstDate: _minDate,
      lastDate: _maxDate,
      helpText: 'To date',
    );
    if (picked != null) {
      if (_mode == _PlanMode.weekly) {
        _from = _startOfWeek(picked);
        _to = _endOfWeek(picked);
      } else {
        _to = DateTime(picked.year, picked.month, picked.day);
      }
      _clampFromTo();
      setState(() {});
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    final choice = await showDialog<DateTime>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Select Month'),
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(DateFormat('MMMM yyyy').format(currentMonth)),
            onTap: () => Navigator.pop(ctx, currentMonth),
          ),
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(DateFormat('MMMM yyyy').format(nextMonth)),
            onTap: () => Navigator.pop(ctx, nextMonth),
          ),
        ],
      ),
    );

    if (choice != null) {
      setState(() => _month = choice);
    }
  }

  DateTime get _finalFrom {
    if (_mode == _PlanMode.monthly) {
      return DateTime(_month.year, _month.month, 1);
    }
    return DateTime(_from.year, _from.month, _from.day);
  }

  DateTime get _finalTo {
    if (_mode == _PlanMode.monthly) {
      return _lastDayOfMonth(_month);
    }
    return DateTime(_to.year, _to.month, _to.day);
  }

  // ---------- Planning logic ----------
  DateTime _addInterval(DateTime from, String interval, int? customDays) {
    switch (interval.toLowerCase()) {
      case 'weekly':
        return from.add(const Duration(days: 7));
      case 'monthly':
        return DateTime(from.year, from.month + 1, from.day);
      case 'annually':
      case 'yearly':
        return DateTime(from.year + 1, from.month, from.day);
      case 'custom':
        final d = (customDays ?? 1);
        return from.add(Duration(days: d > 0 ? d : 1));
      default:
        return DateTime(from.year, from.month + 1, from.day);
    }
  }

  String _intervalLabel(String interval, int? customDays) {
    if (interval.toLowerCase() == 'custom') {
      final d = (customDays ?? 1);
      return 'Every $d days';
    }
    // Capitalize first letter
    return interval.isEmpty
        ? 'Monthly'
        : interval[0].toUpperCase() + interval.substring(1).toLowerCase();
  }

  // ---------- PDF ----------
  Future<Directory> _preferredSaveDir() async {
    if (Platform.isAndroid) {
      final d = Directory('/storage/emulated/0/Download');
      if (await d.exists()) return d;
      final ext = await getExternalStorageDirectory();
      if (ext != null) return ext;
      return await getApplicationDocumentsDirectory();
    } else {
      return await getApplicationDocumentsDirectory();
    }
  }

  Future<void> _generatePlannerPdf() async {
    setState(() => _busy = true);
    try {
      _dfSql.format(_finalFrom);
      final endStr = _dfSql.format(_finalTo);

      // NOTE: fetch any task whose base next_due_date is on/before our window end
      // (so even if it's before the window, we can iterate forward into it)
      final rows = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select(
              'job_seq, task_name, job_description, next_due_date, task_interval, custom_interval, postponed',
            )
            .lte('next_due_date', endStr)
            .neq('postponed', 'yes') // don’t plan postponed tasks
            .order('next_due_date', ascending: true);
      });
      // Build expanded plan
      final List<_PlanRow> plan = [];
      for (final m in (rows as List)) {
        final jobSeq = (m['job_seq'] as num?)?.toInt();
        final taskName = (m['task_name'] as String?) ?? '';
        final desc = (m['job_description'] as String?) ?? '';
        final nextDueStr = (m['next_due_date'] as String?) ?? '';
        final interval = (m['task_interval'] as String?) ?? 'monthly';
        final customDays = (m['custom_interval'] as num?)?.toInt();

        if (jobSeq == null || nextDueStr.isEmpty) continue;

        DateTime due = DateTime.parse(nextDueStr);

        // If the base due is before the window, advance it by interval
        // until it reaches (or passes) the window start.
        while (due.isBefore(_finalFrom)) {
          final next = _addInterval(due, interval, customDays);
          if (next.isAtSameMomentAs(due)) break; // safety
          due = next;
        }

        // Now collect all occurrences that fall inside the window,
        // advancing by interval each time, until we pass the window end.
        while (!due.isAfter(_finalTo)) {
          if (!due.isBefore(_finalFrom)) {
            plan.add(
              _PlanRow(
                jobSeq: jobSeq,
                taskName: taskName,
                description: desc,
                intervalLabel: _intervalLabel(interval, customDays),
                due: due,
              ),
            );
          }
          final next = _addInterval(due, interval, customDays);
          if (next.isAtSameMomentAs(due)) break; // safety
          due = next;
        }
      }

      // Sort by due date, then job id
      plan.sort((a, b) {
        final byDate = a.due.compareTo(b.due);
        if (byDate != 0) return byDate;
        return a.jobSeq.compareTo(b.jobSeq);
      });

      // Prepare PDF assets
      final roboto = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
      );
      final robotoItalic = pw.Font.ttf(
        await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
      );
      final logoBytes = await rootBundle.load('assets/images/app_icon.png');
      final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

      const brandGreen = PdfColor(0.06, 0.20, 0.15);
      const brandGold = PdfColor(0.85, 0.65, 0.20);

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: roboto,
          bold: roboto,
          italic: robotoItalic,
        ),
      );

      // Build table data (with Interval column)
      final headers = <String>[
        'S/N',
        'Job ID',
        'Task Name',
        'Task Description',
        'Interval',
        'Due Date',
      ];

      final data = <List<String>>[];
      for (int i = 0; i < plan.length; i++) {
        final r = plan[i];
        data.add([
          '${i + 1}',
          '${r.jobSeq}',
          r.taskName,
          r.description,
          r.intervalLabel,
          _dfUi.format(r.due),
        ]);
      }

      final title = 'Work Planner';
      final sub =
          'From ${_dfUi.format(_finalFrom)} to ${_dfUi.format(_finalTo)}';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          header: (context) => pw.Container(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 10,
            ),
            decoration: const pw.BoxDecoration(color: brandGreen),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  height: 75,
                  width: 75,
                  margin: const pw.EdgeInsets.only(right: 16),
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Text(
                      "Emville PMS",
                      style: pw.TextStyle(
                        color: brandGold,
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          build: (_) => [
            pw.SizedBox(height: 16),
            pw.Text(
              title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(sub, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 12),
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: pw.BoxDecoration(color: brandGreen),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              headerAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                vertical: 6,
                horizontal: 4,
              ),
              border: null,
              columnWidths: const {
                0: pw.FixedColumnWidth(36), // S/N
                1: pw.FixedColumnWidth(48), // Job ID
                2: pw.FlexColumnWidth(2), // Task Name
                3: pw.FlexColumnWidth(3), // Description
                4: pw.FixedColumnWidth(70), // Interval
                5: pw.FixedColumnWidth(80), // Due Date
              },
            ),
          ],
        ),
      );

      final dir = await _preferredSaveDir();
      final fname =
          'pms_work_planner_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${dir.path}/$fname');
      await file.writeAsBytes(await pdf.save(), flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      await OpenFilex.open(file.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- UI ----------
  Widget _rangeControls() {
    final rs = ResponsiveSize.of(context);
    final fromUi = _dfUi.format(_finalFrom);
    final toUi = _dfUi.format(_finalTo);
    final monthUi = DateFormat('MMMM yyyy').format(_month);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Range',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: rs.font(14),
            )),
        SizedBox(height: rs.space(8)),
        SegmentedButton<_PlanMode>(
          segments: const [
            ButtonSegment(value: _PlanMode.weekly, label: Text('Weekly')),
            ButtonSegment(value: _PlanMode.monthly, label: Text('Monthly')),
            ButtonSegment(value: _PlanMode.custom, label: Text('Custom')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) {
            setState(() => _mode = s.first);
            // snap weekly to current week by default
            if (_mode == _PlanMode.weekly) {
              final now = DateTime.now();
              _from = _startOfWeek(now);
              _to = _endOfWeek(now);
              _clampFromTo();
            }
          },
        ),
        SizedBox(height: rs.space(12)),
        if (_mode == _PlanMode.weekly || _mode == _PlanMode.custom)
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('From', style: TextStyle(fontSize: rs.font(14))),
                  subtitle:
                      Text(fromUi, style: TextStyle(fontSize: rs.font(13))),
                  trailing: IconButton(
                    icon: const Icon(Icons.date_range),
                    onPressed: _busy ? null : _pickFrom,
                  ),
                ),
              ),
              SizedBox(width: rs.space(8)),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('To', style: TextStyle(fontSize: rs.font(14))),
                  subtitle: Text(toUi, style: TextStyle(fontSize: rs.font(13))),
                  trailing: IconButton(
                    icon: const Icon(Icons.date_range),
                    onPressed: _busy ? null : _pickTo,
                  ),
                ),
              ),
            ],
          ),
        if (_mode == _PlanMode.monthly)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Month', style: TextStyle(fontSize: rs.font(14))),
            subtitle: Text(monthUi, style: TextStyle(fontSize: rs.font(13))),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month),
              onPressed: _busy ? null : _pickMonth,
            ),
          ),
        SizedBox(height: rs.space(12)),
        Text(
          'You can plan from today up to the end of next month.',
          style: TextStyle(fontSize: rs.font(12), color: Colors.black54),
        ),
        SizedBox(height: rs.space(16)),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: _gold,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _busy ? null : _generatePlannerPdf,
            icon: _busy
                ? SizedBox(
                    height: rs.space(18),
                    width: rs.space(18),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(_gold),
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text(
              'Generate',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Work Planning',
          style: TextStyle(fontSize: rs.font(20), fontWeight: FontWeight.w700),
        ),
        backgroundColor: _green,
        foregroundColor: _gold,
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: ListView(
              padding: EdgeInsets.all(rs.space(16)),
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 3,
                  margin: EdgeInsets.symmetric(vertical: rs.space(8)),
                  child: Padding(
                    padding: EdgeInsets.all(rs.space(16)),
                    child: _rangeControls(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Model for planning ----------
class _PlanRow {
  _PlanRow({
    required this.jobSeq,
    required this.taskName,
    required this.description,
    required this.intervalLabel,
    required this.due,
  });

  final int jobSeq;
  final String taskName;
  final String description;
  final String intervalLabel;
  final DateTime due;
}
