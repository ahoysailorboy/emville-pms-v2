import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:emville_pms/supabase_call.dart';
// ✅ Responsive helper
import 'package:emville_pms/responsive/responsive.dart';

/// Resize/compress image bytes for PDF (~12 cm tall at print quality)
Future<Uint8List> _preparePhotoForPdf(Uint8List bytes) async {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;

  // ~12 cm at decent DPI → about 1200 px tall (tweak as you like)
  const targetHeight = 1200;
  final resized = decoded.height > targetHeight
      ? img.copyResize(decoded, height: targetHeight)
      : decoded;

  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

class WorkDoneReportPage extends StatefulWidget {
  const WorkDoneReportPage({super.key});

  @override
  State<WorkDoneReportPage> createState() => _WorkDoneReportPageState();
}

enum _RangeMode { weekly, monthly, custom }

class _WorkDoneReportPageState extends State<WorkDoneReportPage> {
  // Emville brand
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  final _sb = Supabase.instance.client;

  _RangeMode _mode = _RangeMode.weekly;

  // Weekly / Custom dates
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  // Monthly (pick any day in month)
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  final _dfSql = DateFormat('yyyy-MM-dd');
  final _dfUi = DateFormat('dd MMM yyyy');

  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _initWeeklyDefault();
  }

  // ---- Range helpers -------------------------------------------------
  void _initWeeklyDefault() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // Dart weekday: Mon=1..Sun=7
    if (today.weekday == DateTime.sunday) {
      _from = today;
      _to = today.add(const Duration(days: 6));
    } else {
      // find most recent Sunday (end of week)
      final mostRecentSunday = today.subtract(
        Duration(days: today.weekday % 7),
      );
      _to = mostRecentSunday;
      _from = mostRecentSunday.subtract(const Duration(days: 6));
    }
    _clampRange();
    setState(() {});
  }

  void _clampRange() {
    final earliest = DateTime(2022, 1, 1);
    final today = DateTime.now();
    if (_from.isBefore(earliest)) _from = earliest;
    if (_to.isBefore(earliest)) _to = earliest;
    if (_from.isAfter(today)) _from = today;
    if (_to.isAfter(today)) _to = today;
    if (_from.isAfter(_to)) {
      _to = _from;
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'From date',
    );
    if (picked != null) {
      if (_mode == _RangeMode.weekly) {
        if (picked.weekday == DateTime.sunday) {
          _from = DateTime(picked.year, picked.month, picked.day);
          _to = _from.add(const Duration(days: 6));
        } else {
          final mostRecentSunday = picked.subtract(
            Duration(days: picked.weekday % 7),
          );
          _to = mostRecentSunday;
          _from = mostRecentSunday.subtract(const Duration(days: 6));
        }
      } else {
        _from = picked;
      }
      _clampRange();
      setState(() {});
    }
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2022, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'To date',
    );
    if (picked != null) {
      if (_mode == _RangeMode.weekly) {
        if (picked.weekday == DateTime.sunday) {
          _to = DateTime(picked.year, picked.month, picked.day);
          _from = _to.subtract(const Duration(days: 6));
        } else {
          final nextSunday = picked.add(
            Duration(days: (7 - picked.weekday) % 7),
          );
          _to = nextSunday;
          _from = _to.subtract(const Duration(days: 6));
        }
      } else {
        _to = picked;
      }
      _clampRange();
      setState(() {});
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5, 1, 1);
    final last = DateTime(now.year + 5, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate:
          first.isBefore(DateTime(2022, 1, 1)) ? DateTime(2022, 1, 1) : first,
      lastDate: last.isAfter(DateTime.now()) ? DateTime.now() : last,
      helpText: 'Pick any day in the month',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month, 1));
    }
  }

  // ---- PDF + Data ----------------------------------------------------
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

  DateTime get _finalFrom {
    if (_mode == _RangeMode.monthly) {
      return DateTime(_month.year, _month.month, 1);
    }
    return DateTime(_from.year, _from.month, _from.day);
  }

  DateTime get _finalTo {
    if (_mode == _RangeMode.monthly) {
      final s = DateTime(_month.year, _month.month, 1);
      return DateTime(s.year, s.month + 1, 0);
    }
    return DateTime(_to.year, _to.month, _to.day);
  }

  String get _reportTitle {
    switch (_mode) {
      case _RangeMode.weekly:
        return 'Weekly Report';
      case _RangeMode.monthly:
        return 'Monthly Report';
      case _RangeMode.custom:
        return 'Custom Report';
    }
  }

  Future<void> _generateWorkDonePdf() async {
    setState(() => _busy = true);
    try {
      final startStr = _dfSql.format(_finalFrom);
      final endStr = _dfSql.format(_finalTo);

      // 1) Fetch from main_pms_db (done within range via last_done_date)
      final mainRows = await supabaseCall(() async {
        return await _sb
            .from('main_pms_db')
            .select(
              'job_seq, task_name, job_description, last_done_date, remarks, attachment_path, done_by',
            )
            .gte('last_done_date', startStr)
            .lte('last_done_date', endStr)
            .order('last_done_date', ascending: true);
      });

      // 2) Fetch from maintenance_history (done_date in range)
      final histRows = await supabaseCall(() async {
        return await _sb
            .from('maintenance_history')
            .select(
              'job_id, task_name, done_date, remarks, attachment_path, done_by',
            )
            .gte('done_date', startStr)
            .lte('done_date', endStr)
            .order('done_date', ascending: true);
      });
      // 3) Merge & map to a common model
      final items = <_WorkItem>[];

      for (final m in (mainRows as List)) {
        items.add(
          _WorkItem(
            date: (m['last_done_date'] as String?) ?? '',
            jobSeq: (m['job_seq'] as num?)?.toInt(),
            taskName: (m['task_name'] as String?) ?? '',
            description: (m['job_description'] as String?) ?? '',
            remarks: (m['remarks'] as String?) ?? '',
            attachmentPath: m['attachment_path'] as String?,
            doneBy: (m['done_by'] as String?) ?? '',
            source: 'main',
          ),
        );
      }

      for (final m in (histRows as List)) {
        items.add(
          _WorkItem(
            date: (m['done_date'] as String?) ?? '',
            jobSeq: (m['job_id'] as num?)?.toInt(),
            taskName: (m['task_name'] as String?) ?? '',
            description: '', // history didn’t store description
            remarks: (m['remarks'] as String?) ?? '',
            attachmentPath: m['attachment_path'] as String?,
            doneBy: (m['done_by'] as String?) ?? '',
            source: 'history',
          ),
        );
      }

      // 4) Sort chronologically
      items.sort((a, b) => a.date.compareTo(b.date));

      // 5) Prepare brand assets
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

      // 6) Download & prepare images ahead of time
      final rawPhotos = <int, Uint8List?>{};
      for (int i = 0; i < items.length; i++) {
        final path = items[i].attachmentPath;
        if (path == null || path.trim().isEmpty) {
          rawPhotos[i] = null;
          continue;
        }
        try {
          final url = await supabaseCall(() async {
            return await _sb.storage
                .from('maintenance_done')
                .createSignedUrl(path, 600);
          });
          final resp = await http.get(Uri.parse(url));
          rawPhotos[i] = (resp.statusCode == 200) ? resp.bodyBytes : null;
        } catch (_) {
          rawPhotos[i] = null;
        }
      }

      final preparedPhotos = <int, Uint8List?>{};
      for (int i = 0; i < items.length; i++) {
        final raw = rawPhotos[i];
        if (raw == null) {
          preparedPhotos[i] = null;
          continue;
        }
        try {
          preparedPhotos[i] = await _preparePhotoForPdf(raw);
        } catch (_) {
          preparedPhotos[i] = raw; // fallback to original
        }
      }

      // 7) Build PDF
      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(
          base: roboto,
          bold: roboto,
          italic: robotoItalic,
        ),
      );

      final subTitle =
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
              _reportTitle,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(subTitle, style: const pw.TextStyle(fontSize: 12)),
            pw.SizedBox(height: 12),

            // Itemized list
            ...List.generate(items.length, (i) {
              final it = items[i];
              final dateUi =
                  it.date.isEmpty ? '—' : _dfUi.format(DateTime.parse(it.date));
              final prepared = preparedPhotos[i];
              final photoProvider =
                  (prepared != null) ? pw.MemoryImage(prepared) : null;

              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.all(8),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.5,
                      ),
                      borderRadius: pw.BorderRadius.circular(6),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          '${it.taskName} ${it.jobSeq != null ? "(Job ${it.jobSeq})" : ""}',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 12,
                            // ignore: deprecated_member_use
                            color: PdfColor.fromInt(_green.value),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Date: $dateUi',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        if (it.description.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Description: ${it.description}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                        if (it.doneBy.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'Done by: ${it.doneBy}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                        if (it.remarks.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            'Remarks:',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                          pw.Text(
                            it.remarks,
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        ],
                        if (photoProvider != null) ...[
                          pw.SizedBox(height: 6),
                          pw.Center(
                            child: pw.Container(
                              // Target print height = 12 cm; width scales proportionally
                              height: 12 * PdfPageFormat.cm,
                              decoration: pw.BoxDecoration(
                                borderRadius: pw.BorderRadius.circular(6),
                                border: pw.Border.all(
                                  color: PdfColors.grey300,
                                  width: 0.5,
                                ),
                              ),
                              child: pw.ClipRRect(
                                horizontalRadius: 6,
                                verticalRadius: 6,
                                child: pw.FittedBox(
                                  fit: pw.BoxFit.fitHeight,
                                  child: pw.Image(photoProvider),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 10),
                ],
              );
            }),
          ],
        ),
      );

      final dir = await _preferredSaveDir();
      final fname =
          'pms_work_done_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
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

  // ---- UI ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    final earliest = DateFormat('dd MMM yyyy').format(DateTime(2022, 1, 1));
    final fromUi = _dfUi.format(_finalFrom);
    final toUi = _dfUi.format(_finalTo);
    final monthUi = DateFormat('MMMM yyyy').format(_month);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Work Done Report',
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
                Text(
                  'Range',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: rs.font(14),
                  ),
                ),
                SizedBox(height: rs.space(8)),
                SegmentedButton<_RangeMode>(
                  segments: const [
                    ButtonSegment(
                        value: _RangeMode.weekly, label: Text('Weekly')),
                    ButtonSegment(
                        value: _RangeMode.monthly, label: Text('Monthly')),
                    ButtonSegment(
                        value: _RangeMode.custom, label: Text('Custom')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) {
                    setState(() => _mode = s.first);
                    if (_mode == _RangeMode.weekly) _initWeeklyDefault();
                  },
                ),
                SizedBox(height: rs.space(12)),
                if (_mode == _RangeMode.weekly || _mode == _RangeMode.custom)
                  Row(
                    children: [
                      Expanded(
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('From',
                              style: TextStyle(fontSize: rs.font(14))),
                          subtitle: Text(fromUi,
                              style: TextStyle(fontSize: rs.font(13))),
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
                          title: Text('To',
                              style: TextStyle(fontSize: rs.font(14))),
                          subtitle: Text(toUi,
                              style: TextStyle(fontSize: rs.font(13))),
                          trailing: IconButton(
                            icon: const Icon(Icons.date_range),
                            onPressed: _busy ? null : _pickTo,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_mode == _RangeMode.monthly)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('Month', style: TextStyle(fontSize: rs.font(14))),
                    subtitle:
                        Text(monthUi, style: TextStyle(fontSize: rs.font(13))),
                    trailing: IconButton(
                      icon: const Icon(Icons.calendar_month),
                      onPressed: _busy ? null : _pickMonth,
                    ),
                  ),
                SizedBox(height: rs.space(8)),
                Text(
                  'No future dates. Earliest: $earliest',
                  style:
                      TextStyle(fontSize: rs.font(12), color: Colors.black54),
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
                    onPressed: _busy ? null : _generateWorkDonePdf,
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
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- Model used for PDF ----------
class _WorkItem {
  _WorkItem({
    required this.date, // yyyy-MM-dd
    required this.jobSeq,
    required this.taskName,
    required this.description,
    required this.remarks,
    required this.attachmentPath,
    required this.doneBy,
    required this.source, // 'main' | 'history'
  });

  final String date;
  final int? jobSeq;
  final String taskName;
  final String description;
  final String remarks;
  final String? attachmentPath;
  final String doneBy;
  final String source;
}
