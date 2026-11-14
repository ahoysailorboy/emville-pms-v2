import 'package:emville_pms/ui/report_options_page.dart';
import 'package:emville_pms/ui/emville_pdf_letterhead.dart';
// lib/features/accounts/presentation/report_pl_page.dart
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ✅ Responsive helper (same convention as other updated pages)

class ReportPlPage extends StatefulWidget {
  const ReportPlPage({super.key});

  @override
  State<ReportPlPage> createState() => _ReportPlPageState();
}

enum _RangeMode { monthly, quarterly, annual }

enum _TxStatusFilter { approved, pending, all }

enum _ExportKind { excel, pdf }

enum _Quarter { q1, q2, q3, q4 } // (FY) Q1: Apr–Jun, ... Q4: Jan–Mar

class _ReportPlPageState extends State<ReportPlPage> {
  final _sb = Supabase.instance.client;

  // Emville theme

  // Controls
  _RangeMode _mode = _RangeMode.monthly;
  _TxStatusFilter _status = _TxStatusFilter.approved;
  _ExportKind _export = _ExportKind.excel;

  // Monthly
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Quarterly / Annual – use FY start year
  int _fyStartYear = _defaultFyStart();
  _Quarter _quarter = _defaultQuarterForNow();

  // Custom helpers
  static int _defaultFyStart() {
    final now = DateTime.now();
    return (now.month >= 4) ? now.year : now.year - 1;
  }

  static _Quarter _defaultQuarterForNow() {
    final m = DateTime.now().month;
    if (m >= 4 && m <= 6) return _Quarter.q1;
    if (m >= 7 && m <= 9) return _Quarter.q2;
    if (m >= 10 && m <= 12) return _Quarter.q3;
    return _Quarter.q4; // Jan–Mar
  }

  // ---------- Range calculation ----------
  DateTime get _rangeStart {
    switch (_mode) {
      case _RangeMode.monthly:
        return DateTime(_month.year, _month.month, 1);
      case _RangeMode.quarterly:
        return _quarterStart(_fyStartYear, _quarter);
      case _RangeMode.annual:
        return DateTime(_fyStartYear, 4, 1);
    }
  }

  DateTime get _rangeEnd {
    switch (_mode) {
      case _RangeMode.monthly:
        final s = DateTime(_month.year, _month.month, 1);
        return DateTime(s.year, s.month + 1, 0);
      case _RangeMode.quarterly:
        return _quarterEnd(_fyStartYear, _quarter);
      case _RangeMode.annual:
        return DateTime(_fyStartYear + 1, 3, 31);
    }
  }

  static DateTime _quarterStart(int fyStart, _Quarter q) {
    switch (q) {
      case _Quarter.q1: // Apr–Jun
        return DateTime(fyStart, 4, 1);
      case _Quarter.q2: // Jul–Sep
        return DateTime(fyStart, 7, 1);
      case _Quarter.q3: // Oct–Dec
        return DateTime(fyStart, 10, 1);
      case _Quarter.q4: // Jan–Mar (next calendar year)
        return DateTime(fyStart + 1, 1, 1);
    }
  }

  static DateTime _quarterEnd(int fyStart, _Quarter q) {
    switch (q) {
      case _Quarter.q1: // Apr–Jun
        return DateTime(fyStart, 6, 30);
      case _Quarter.q2: // Jul–Sep
        return DateTime(fyStart, 9, 30);
      case _Quarter.q3: // Oct–Dec
        return DateTime(fyStart, 12, 31);
      case _Quarter.q4: // Jan–Mar
        return DateTime(fyStart + 1, 3, 31);
    }
  }

  String get _statusFilterSqlValue {
    switch (_status) {
      case _TxStatusFilter.approved:
        return 'approved';
      case _TxStatusFilter.pending:
        return 'pending';
      case _TxStatusFilter.all:
        return 'all';
    }
  }

  // ---------- Fetch data ----------
  final _dfSql = DateFormat('yyyy-MM-dd');

  Future<List<_PlRow>> _fetchPlRows() async {
    final startStr = _dfSql.format(_rangeStart);
    final endStr = _dfSql.format(_rangeEnd);

    var q = _sb.from('main_ledger').select(
          'date, amount, transaction_type, payee_payer_name, remarks, transaction_status',
        ) as PostgrestFilterBuilder;

    q = q.gte('date', startStr).lte('date', endStr);
    if (_status != _TxStatusFilter.all) {
      q = q.eq('transaction_status', _statusFilterSqlValue);
    }

    final rows = await q.order('date', ascending: true);
    return ((rows ?? []) as List)
        .map<_PlRow>(
          (m) => _PlRow(
            dateStr: (m['date'] as String?) ?? '',
            amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
            isIncome: (m['transaction_type'] as String?) == 'income',
            details: _composeDetails(
              m['payee_payer_name'] as String?,
              m['remarks'] as String?,
            ),
          ),
        )
        .toList();
  }

  String _composeDetails(String? a, String? b) {
    final x = (a ?? '').trim();
    final y = (b ?? '').trim();
    if (x.isEmpty && y.isEmpty) return '';
    if (x.isEmpty) return y;
    if (y.isEmpty) return x;
    return '$x — $y';
  }

  // ---------- Excel helpers ----------
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

  // ---------- Export: Excel ----------
  Future<void> _exportExcel(List<_PlRow> rows) async {
    final excel = Excel.createExcel();
    final sheet = excel['Profit & Loss'];
    final dfOut = DateFormat('dd-MM-yyyy');

    String fmtDate(String s) {
      if (s.isEmpty) return '';
      try {
        return dfOut.format(DateTime.parse(s));
      } catch (_) {
        return s;
      }
    }

    int r = 0;

    _writeRow(sheet, r++, <dynamic>['Profit & Loss Statement']);
    _writeRow(sheet, r++, <dynamic>[_rangeTitle()]);
    _writeRow(sheet, r++, <dynamic>['Status: ${_status.name}']);
    r++;

    _writeRow(sheet, r++, <dynamic>[
      'Date',
      'Details',
      'Income (₹)',
      'Expense (₹)',
    ]);

    double totIncome = 0.0, totExpense = 0.0;

    for (final x in rows) {
      if (x.isIncome) {
        totIncome += x.amount;
      } else {
        totExpense += x.amount;
      }
      _writeRow(sheet, r++, <dynamic>[
        fmtDate(x.dateStr),
        x.details,
        x.isIncome ? x.amount : '',
        x.isIncome ? '' : x.amount,
      ]);
    }

    final net = totIncome - totExpense;
    r++;
    _writeRow(sheet, r++, <dynamic>['', 'Total Income', totIncome, '']);
    _writeRow(sheet, r++, <dynamic>['', 'Total Expense', '', totExpense]);
    _writeRow(sheet, r++, <dynamic>['', 'Net Profit / (Loss)', net, '']);

    final dir = await _preferredSaveDir();
    final fname =
        'pl_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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

  // ---------- Export: PDF (LANDSCAPE) ----------
  Future<void> _exportPdf(List<_PlRow> rows) async {
    // Fonts
    final roboto = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final robotoItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );

    // Logo
    final logoBytes = await rootBundle.load('assets/brand/emville-logo.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // Brand colors
    final brandGreen = const PdfColor(0.06, 0.20, 0.15); // #103329-ish

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: roboto,
        bold: roboto,
        italic: robotoItalic,
      ),
    );

    final reportTitle = 'Profit & Loss Statement';
    final subTitle = _rangeTitle();
    final statusLine = 'Status: ${_status.name}';
    final dfOut = DateFormat('dd-MM-yyyy');

    // Table rows
    final headers = <String>['Date', 'Details', 'Income (₹)', 'Expense (₹)'];
    final dataRows = <List<String>>[];
    double totIncome = 0.0, totExpense = 0.0;

    for (final x in rows) {
      if (x.isIncome) {
        totIncome += x.amount;
      } else {
        totExpense += x.amount;
      }
      dataRows.add([
        x.dateStr.isEmpty ? '' : dfOut.format(DateTime.parse(x.dateStr)),
        x.details,
        x.isIncome ? x.amount.toStringAsFixed(2) : '',
        x.isIncome ? '' : x.amount.toStringAsFixed(2),
      ]);
    }

    final net = totIncome - totExpense;

    // Blank + Totals
    dataRows.add(['', '', '', '']);
    dataRows.add(['', 'Total Income', totIncome.toStringAsFixed(2), '']);
    dataRows.add(['', 'Total Expense', '', totExpense.toStringAsFixed(2)]);
    dataRows.add(['', 'Net Profit / (Loss)', net.toStringAsFixed(2), '']);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
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
            headers: headers,
            data: dataRows,
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
              0: const pw.FixedColumnWidth(90),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FixedColumnWidth(100),
              3: const pw.FixedColumnWidth(100),
            },
          ),
        ],
      ),
    );

    final dir = await _preferredSaveDir();
    final fname =
        'pl_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${dir.path}/$fname');
    await file.writeAsBytes(await pdf.save(), flush: true);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      await OpenFilex.open(file.path);
    }
  }

  // ---------- UI helpers ----------
  String _rangeTitle() {
    switch (_mode) {
      case _RangeMode.monthly:
        return 'Month: ${DateFormat('MMMM yyyy').format(_month)}';
      case _RangeMode.quarterly:
        final qLabel = switch (_quarter) {
          _Quarter.q1 => 'Apr–Jun',
          _Quarter.q2 => 'Jul–Sep',
          _Quarter.q3 => 'Oct–Dec',
          _Quarter.q4 => 'Jan–Mar',
        };
        return 'Quarter: $qLabel • FY $_fyStartYear–${_fyStartYear + 1}';
      case _RangeMode.annual:
        return 'Financial Year: $_fyStartYear–${_fyStartYear + 1}';
    }
  }

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

  // ---------- Build (Emville layout only) ----------
  @override
  Widget build(BuildContext context) => ReportOptionsPage(
        title: 'Profit & loss report',
        period: _mode.name,
        periodLabels: const {
          'monthly': 'Monthly',
          'quarterly': 'Quarterly',
          'annual': 'Yearly (FY)'
        },
        onPeriod: (v) => setState(
            () => _mode = _RangeMode.values.firstWhere((m) => m.name == v)),
        dateSelection: _mode == _RangeMode.monthly
            ? reportDateField(
                'Month', DateFormat('MMMM yyyy').format(_month), _pickMonth)
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_mode == _RangeMode.quarterly) ...[
                  DropdownButtonFormField<_Quarter>(
                      initialValue: _quarter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          labelText: 'Quarter',
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12)),
                      items: const [
                        DropdownMenuItem(
                            value: _Quarter.q1, child: Text('Apr–Jun')),
                        DropdownMenuItem(
                            value: _Quarter.q2, child: Text('Jul–Sep')),
                        DropdownMenuItem(
                            value: _Quarter.q3, child: Text('Oct–Dec')),
                        DropdownMenuItem(
                            value: _Quarter.q4, child: Text('Jan–Mar'))
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _quarter = v);
                      }),
                  const SizedBox(height: 16)
                ],
                reportYearField(_fyStartYear, _defaultFyStart(),
                    (v) => setState(() => _fyStartYear = v)),
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
            final rows = await _fetchPlRows();
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

// ---------- Models ----------
class _PlRow {
  _PlRow({
    required this.dateStr, // yyyy-MM-dd
    required this.amount,
    required this.isIncome,
    required this.details,
  });

  final String dateStr;
  final double amount;
  final bool isIncome;
  final String details;
}
