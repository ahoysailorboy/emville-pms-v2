import 'package:emville_pms/ui/report_options_page.dart';
import 'package:emville_pms/ui/emville_pdf_letterhead.dart';
// lib/features/accounts/presentation/report_income_page.dart
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';

// ✅ Responsive barrel

class ReportIncomePage extends StatefulWidget {
  const ReportIncomePage({super.key});

  @override
  State<ReportIncomePage> createState() => _ReportIncomePageState();
}

enum _RangeMode { monthly, yearly, custom }

enum _TxStatusFilter { approved, pending, all }

enum _ExportKind { excel, pdf }

class _ReportIncomePageState extends State<ReportIncomePage> {
  final _sb = Supabase.instance.client;

  // Emville theme

  // Controls
  _RangeMode _mode = _RangeMode.monthly;
  _TxStatusFilter _status = _TxStatusFilter.approved;
  _ExportKind _export = _ExportKind.excel;

  // Monthly
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Yearly (FY: Apr 1 → Mar 31) — store FY start year
  int _fyStartYear = _defaultFyStart();

  // Custom range
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  static int _defaultFyStart() {
    final now = DateTime.now();
    return (now.month >= 4) ? now.year : now.year - 1;
  }

  DateTime get _rangeStart {
    switch (_mode) {
      case _RangeMode.monthly:
        return DateTime(_month.year, _month.month, 1);
      case _RangeMode.yearly:
        return DateTime(_fyStartYear, 4, 1);
      case _RangeMode.custom:
        return DateTime(_from.year, _from.month, _from.day);
    }
  }

  DateTime get _rangeEnd {
    switch (_mode) {
      case _RangeMode.monthly:
        final start = DateTime(_month.year, _month.month, 1);
        return DateTime(start.year, start.month + 1, 0);
      case _RangeMode.yearly:
        return DateTime(_fyStartYear + 1, 3, 31);
      case _RangeMode.custom:
        return DateTime(_to.year, _to.month, _to.day);
    }
  }

  String get _statusValue {
    switch (_status) {
      case _TxStatusFilter.approved:
        return 'approved';
      case _TxStatusFilter.pending:
        return 'pending';
      case _TxStatusFilter.all:
        return 'all';
    }
  }

  // ----------------------------
  // DATA
  // ----------------------------
  final _dfApi = DateFormat('yyyy-MM-dd'); // for Supabase filters

  Future<List<_IncomeRow>> _fetchIncomeRows() async {
    final startStr = _dfApi.format(_rangeStart);
    final endStr = _dfApi.format(_rangeEnd);

    var q = _sb.from('main_ledger').select(
          'date, amount, payee_payer_name, remarks, transaction_status, transaction_type',
        ) as PostgrestFilterBuilder;

    q = q
        .gte('date', startStr)
        .lte('date', endStr)
        .eq('transaction_type', 'income');

    if (_status != _TxStatusFilter.all) {
      q = q.eq('transaction_status', _statusValue);
    }

    final rows = await q.order('date', ascending: true);
    final list = <_IncomeRow>[];
    for (final m in (rows ?? []) as List) {
      list.add(
        _IncomeRow(
          dateStr: (m['date'] as String?) ?? '',
          amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
          details: _composeDetails(
            m['payee_payer_name'] as String?,
            m['remarks'] as String?,
          ),
        ),
      );
    }
    return list;
  }

  String _composeDetails(String? who, String? remarks) {
    final a = (who ?? '').trim();
    final b = (remarks ?? '').trim();
    if (a.isEmpty && b.isEmpty) return '';
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a — $b';
  }

  // ----------------------------
  // SAVE DIR
  // ----------------------------
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

  // ----------------------------
  // EXCEL (CellValue API)
  // ----------------------------
  void _writeRow(Sheet sheet, int row, List<dynamic> values) {
    for (int col = 0; col < values.length; col++) {
      final ci = CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row);
      final v = values[col];
      if (v == null) {
        sheet.cell(ci).value = TextCellValue('');
      } else if (v is num) {
        sheet.cell(ci).value = DoubleCellValue(v.toDouble());
      } else {
        sheet.cell(ci).value = TextCellValue(v.toString());
      }
    }
  }

  Future<void> _exportExcel(List<_IncomeRow> rows) async {
    final excel = Excel.createExcel();
    final sheet = excel['Income Report'];
    final dfOut = DateFormat('dd-MM-yyyy');

    String fmt(String s) {
      if (s.isEmpty) return '';
      try {
        return dfOut.format(DateTime.parse(s));
      } catch (_) {
        return s;
      }
    }

    int r = 0;
    _writeRow(sheet, r++, <dynamic>['Income Report']);
    _writeRow(sheet, r++, <dynamic>[_rangeTitle()]);
    _writeRow(sheet, r++, <dynamic>['Status: ${_status.name}']);
    r++;

    _writeRow(sheet, r++, <dynamic>['Date', 'Details', 'Amount (₹)']);

    double total = 0.0;

    for (final x in rows) {
      total += x.amount;
      _writeRow(sheet, r++, <dynamic>[fmt(x.dateStr), x.details, x.amount]);
    }

    // Blank line + TOTAL
    r++;
    _writeRow(sheet, r++, <dynamic>['', 'Total', total]);

    final dir = await _preferredSaveDir();
    final fname =
        'income_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final file = File('${dir.path}/$fname');
    final bytes = excel.encode();
    await file.writeAsBytes(bytes!, flush: true);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      await OpenFilex.open(file.path);
    }
  }

  // ----------------------------
  // PDF
  // ----------------------------
  Future<void> _exportPdf(List<_IncomeRow> rows) async {
    final roboto = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final robotoItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );
    final logoBytes = await rootBundle.load('assets/brand/emville-logo.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final brandGreen = const PdfColor(0.06, 0.20, 0.15);

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: roboto,
        bold: roboto,
        italic: robotoItalic,
      ),
    );

    final reportTitle = 'Income Report';
    final subTitle = _rangeTitle();
    final statusLine = 'Status: ${_status.name}';
    final dateFmt = DateFormat('dd-MM-yyyy');

    final tableHeaders = <String>['Date', 'Details', 'Amount (₹)'];

    final tableRows = <List<String>>[];
    double total = 0.0;

    for (final x in rows) {
      total += x.amount;
      tableRows.add([
        x.dateStr.isEmpty ? '' : dateFmt.format(DateTime.parse(x.dateStr)),
        x.details,
        x.amount.toStringAsFixed(2),
      ]);
    }

    // Blank line + TOTAL row
    tableRows.add(['', '', '']);
    tableRows.add(['', 'Total', total.toStringAsFixed(2)]);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => emvillePdfLetterhead(logo),
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
            reportTitle,
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(subTitle, style: const pw.TextStyle(fontSize: 12)),
          pw.Text(statusLine, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: tableHeaders,
            data: tableRows,
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
            headerDecoration: pw.BoxDecoration(color: brandGreen),
            cellAlignment: pw.Alignment.centerLeft,
            headerAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 10),
            cellPadding: const pw.EdgeInsets.symmetric(
              vertical: 6,
              horizontal: 4,
            ),
            border: null,
            columnWidths: {
              0: const pw.FixedColumnWidth(72),
              1: const pw.FlexColumnWidth(3),
              2: const pw.FixedColumnWidth(80),
            },
          ),
        ],
      ),
    );

    final dir = await _preferredSaveDir();
    final fname =
        'income_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${dir.path}/$fname');
    await file.writeAsBytes(await pdf.save(), flush: true);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      await OpenFilex.open(file.path);
    }
  }

  String _rangeTitle() {
    switch (_mode) {
      case _RangeMode.monthly:
        return 'Month: ${DateFormat('MMMM yyyy').format(_month)}';
      case _RangeMode.yearly:
        return 'Financial Year: $_fyStartYear–${_fyStartYear + 1}';
      case _RangeMode.custom:
        final df = DateFormat('dd-MM-yyyy');
        return 'From ${df.format(_rangeStart)} to ${df.format(_rangeEnd)}';
    }
  }

  // ----------------------------
  // UI HELPERS
  // ----------------------------
  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 5, 1, 1);
    final last = DateTime(now.year + 5, 12, 31);
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: first,
      lastDate: last,
      helpText: 'Pick any day in the month',
    );
    if (picked != null) {
      setState(() => _month = DateTime(picked.year, picked.month, 1));
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'From date',
    );
    if (picked != null) setState(() => _from = picked);
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
      helpText: 'To date',
    );
    if (picked != null) setState(() => _to = picked);
  }

  // ----------------------------
  // BUILD (Emville layout only)
  // ----------------------------
  @override
  Widget build(BuildContext context) => ReportOptionsPage(
        title: 'Income report',
        period: _mode.name,
        periodLabels: const {
          'monthly': 'Monthly',
          'yearly': 'Yearly (FY)',
          'custom': 'From–To'
        },
        onPeriod: (v) => setState(
            () => _mode = _RangeMode.values.firstWhere((m) => m.name == v)),
        dateSelection: _mode == _RangeMode.monthly
            ? reportDateField(
                'Month', DateFormat('MMMM yyyy').format(_month), _pickMonth)
            : _mode == _RangeMode.yearly
                ? reportYearField(_fyStartYear, _defaultFyStart(),
                    (v) => setState(() => _fyStartYear = v))
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: reportDateField('From',
                            DateFormat('d MMM yyyy').format(_from), _pickFrom)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: reportDateField('To',
                            DateFormat('d MMM yyyy').format(_to), _pickTo))
                  ]),
        status: _status.name,
        onStatus: (v) => setState(() =>
            _status = _TxStatusFilter.values.firstWhere((s) => s.name == v)),
        format: _export.name,
        onFormat: (v) => setState(
            () => _export = _ExportKind.values.firstWhere((e) => e.name == v)),
        rangeSummary: _rangeTitle(),
        onGenerate: () async {
          try {
            final rows = await _fetchIncomeRows();
            if (_export == _ExportKind.excel) {
              await _exportExcel(rows);
            } else {
              await _exportPdf(rows);
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              // ignore: use_build_context_synchronously
              context,
            ).showSnackBar(SnackBar(content: Text('Failed: $e')));
          }
        },
      );
}

class _IncomeRow {
  _IncomeRow({
    required this.dateStr, // yyyy-MM-dd
    required this.amount,
    required this.details,
  });

  final String dateStr;
  final double amount;
  final String details;
}
