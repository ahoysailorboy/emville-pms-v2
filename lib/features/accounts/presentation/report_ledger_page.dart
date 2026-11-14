import 'package:emville_pms/ui/emville_widgets.dart';
import 'package:emville_pms/ui/report_options_page.dart';
import 'package:emville_pms/ui/emville_pdf_letterhead.dart';
import '../data/finance_access.dart';
// lib/features/accounts/presentation/report_ledger_page.dart
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:flutter/services.dart' show rootBundle;

// ✅ Responsive helper (same one used elsewhere in the app)

class ReportLedgerPage extends StatefulWidget {
  const ReportLedgerPage({super.key});
  @override
  State<ReportLedgerPage> createState() => _ReportAccessState();
}

class _ReportAccessState extends State<ReportLedgerPage> {
  late final _access = FinanceAccess.isOwnerOrAdmin(Supabase.instance.client);
  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
      future: _access,
      builder: (context, snapshot) {
        if (snapshot.data == true) return const _ProtectedLedgerReport();
        return EmvillePage(
            child: Center(
                child: Text(snapshot.connectionState == ConnectionState.done
                    ? 'Only owners and admins can view main ledger balances.'
                    : 'Loading…')));
      });
}

class _ProtectedLedgerReport extends StatefulWidget {
  const _ProtectedLedgerReport();

  @override
  State<_ProtectedLedgerReport> createState() => __ProtectedLedgerReportState();
}

enum _RangeMode { monthly, yearly, custom }

enum _TxStatusFilter { approved, pending, all }

enum _ExportKind { excel, pdf }

class __ProtectedLedgerReportState extends State<_ProtectedLedgerReport> {
  final _sb = Supabase.instance.client;

  // Emville theme

  // Controls
  _RangeMode _mode = _RangeMode.monthly;
  _TxStatusFilter _status = _TxStatusFilter.approved;
  _ExportKind _export = _ExportKind.excel;

  // Monthly
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Yearly (Financial year: Apr 1 → Mar 31). Store the FY start year.
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

  // ----------------------------
  // DATA MODEL
  // ----------------------------
  final _df = DateFormat('yyyy-MM-dd');

  Future<_ReportData> _fetchLedgerData() async {
    final startStr = _df.format(_rangeStart);
    final endStr = _df.format(_rangeEnd);

    final opening = await _openingBalanceBefore(startStr);

    var q = _sb.from('main_ledger').select(
          'date, amount, transaction_type, payee_payer_name, remarks, transaction_status',
        ) as PostgrestFilterBuilder;

    q = q.gte('date', startStr).lte('date', endStr);

    if (_status != _TxStatusFilter.all) {
      q = q.eq('transaction_status', _statusFilterSqlValue);
    }

    final rows = await q.order('date', ascending: true);
    final items = ((rows ?? []) as List)
        .map<_Row>(
          (m) => _Row(
            date: (m['date'] as String?) ?? '',
            amount: (m['amount'] as num?)?.toDouble() ?? 0.0,
            isIncome: (m['transaction_type'] as String?) == 'income',
            details: _composeDetails(
              m['payee_payer_name'] as String?,
              m['remarks'] as String?,
            ),
          ),
        )
        .toList();

    return _ReportData(openingBalance: opening, items: items);
  }

  String _composeDetails(String? whom, String? remarks) {
    final a = (whom ?? '').trim();
    final b = (remarks ?? '').trim();
    if (a.isEmpty && b.isEmpty) return '';
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    return '$a — $b';
  }

  Future<double> _openingBalanceBefore(String startDate) async {
    var q = _sb
            .from('main_ledger')
            .select('amount, transaction_type, transaction_status')
        as PostgrestFilterBuilder;

    q = q.lt('date', startDate);

    if (_status != _TxStatusFilter.all) {
      q = q.eq('transaction_status', _statusFilterSqlValue);
    }

    final rows = await q;
    double bal = 0.0;
    for (final r in (rows ?? []) as List) {
      final amt = (r['amount'] as num?)?.toDouble() ?? 0.0;
      final isIncome = (r['transaction_type'] as String?) == 'income';
      bal += isIncome ? amt : -amt;
    }
    return bal;
  }

  // ----------------------------
  // EXCEL EXPORT
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

  Future<void> _exportExcel(_ReportData data) async {
    final excel = Excel.createExcel();
    final sheet = excel['Main Ledger'];
    final dfOut = DateFormat('dd-MM-yyyy');

    String fmtDateStr(String s) {
      if (s.isEmpty) return '';
      try {
        return dfOut.format(DateTime.parse(s));
      } catch (_) {
        return s;
      }
    }

    int row = 0;

    _writeRow(sheet, row++, <dynamic>['Main Ledger Report']);
    _writeRow(sheet, row++, <dynamic>[_rangeTitle()]);
    _writeRow(sheet, row++, <dynamic>['Status: ${_status.name}']);
    row++;

    _writeRow(sheet, row++, <dynamic>[
      'Date',
      'Details',
      'Debit (₹)',
      'Credit (₹)',
      'Balance (₹)',
    ]);

    double running = data.openingBalance;
    _writeRow(sheet, row++, <dynamic>[
      dfOut.format(_rangeStart),
      'Opening Balance',
      '',
      '',
      running,
    ]);

    for (final r in data.items) {
      if (r.isIncome) {
        running += r.amount;
      } else {
        running -= r.amount;
      }
      _writeRow(sheet, row++, <dynamic>[
        fmtDateStr(r.date),
        r.details,
        r.isIncome ? r.amount : '',
        r.isIncome ? '' : r.amount,
        running,
      ]);
    }

    row++;
    _writeRow(sheet, row++, <dynamic>[
      dfOut.format(_rangeEnd),
      'Closing Balance',
      '',
      '',
      running,
    ]);

    final totalIncome = data.items
        .where((e) => e.isIncome)
        .fold<double>(0.0, (p, e) => p + e.amount);
    final totalExpense = data.items
        .where((e) => !e.isIncome)
        .fold<double>(0.0, (p, e) => p + e.amount);

    row += 2;
    _writeRow(sheet, row++, <dynamic>['', 'Total Income', totalIncome, '', '']);
    _writeRow(sheet, row++, <dynamic>[
      '',
      'Total Expense',
      '',
      totalExpense,
      '',
    ]);

    final dir = await _preferredSaveDir();
    final fname =
        'main_ledger_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final file = File('${dir.path}/$fname');
    final bytes = excel.encode();
    await file.writeAsBytes(bytes!, flush: true);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
    }
    await OpenFilex.open(file.path);
  }

  Future<void> _exportPdf(_ReportData data) async {
    final roboto = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final robotoItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );

    final logoBytes = await rootBundle.load('assets/brand/emville-logo.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    final brandGreen = const PdfColor(0.06, 0.20, 0.15); // ~ #103329

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: roboto,
        bold: roboto,
        italic: robotoItalic,
      ),
    );

    final reportTitle = 'Main Ledger Report';
    final subTitle = _rangeTitle();
    final statusLine = 'Status: ${_status.name}';

    final headers = <String>[
      'Date',
      'Details',
      'Debit (₹)',
      'Credit (₹)',
      'Balance (₹)',
    ];

    final dateFmtDisp = DateFormat('dd-MM-yyyy');
    double running = data.openingBalance;
    final bodyRows = <List<String>>[];

    bodyRows.add([
      dateFmtDisp.format(_rangeStart),
      'Opening Balance',
      '',
      '',
      running.toStringAsFixed(2),
    ]);

    double totalIncome = 0, totalExpense = 0;

    for (final r in data.items) {
      if (r.isIncome) {
        running += r.amount;
        totalIncome += r.amount;
      } else {
        running -= r.amount;
        totalExpense += r.amount;
      }
      bodyRows.add([
        (r.date.isEmpty ? '' : dateFmtDisp.format(DateTime.parse(r.date))),
        r.details,
        r.isIncome ? r.amount.toStringAsFixed(2) : '',
        r.isIncome ? '' : r.amount.toStringAsFixed(2),
        running.toStringAsFixed(2),
      ]);
    }

    bodyRows.add(['', '', '', '', '']);
    bodyRows.add([
      dateFmtDisp.format(_rangeEnd),
      'Closing Balance',
      '',
      '',
      running.toStringAsFixed(2),
    ]);

    bodyRows.add(['', '', '', '', '']);
    bodyRows.add(['', '', '', '', '']);
    bodyRows.add(['', '', '', '', '']);
    bodyRows.add(['', 'Total Income', totalIncome.toStringAsFixed(2), '', '']);
    bodyRows.add([
      '',
      'Total Expense',
      '',
      totalExpense.toStringAsFixed(2),
      '',
    ]);

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
            headers: headers,
            data: bodyRows,
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
              2: const pw.FixedColumnWidth(70),
              3: const pw.FixedColumnWidth(70),
              4: const pw.FixedColumnWidth(80),
            },
          ),
        ],
      ),
    );

    final dir = await _preferredSaveDir();
    final fname =
        'main_ledger_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
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
        return 'From ${_df.format(_rangeStart)} to ${_df.format(_rangeEnd)}';
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
  // BUILD (layout only themed)
  // ----------------------------
  @override
  Widget build(BuildContext context) => ReportOptionsPage(
        title: 'Main ledger report',
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
            final data = await _fetchLedgerData();
            if (_export == _ExportKind.excel) {
              await _exportExcel(data);
            } else {
              await _exportPdf(data);
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
class _ReportData {
  const _ReportData({required this.openingBalance, required this.items});
  final double openingBalance;
  final List<_Row> items;
}

class _Row {
  _Row({
    required this.date, // yyyy-MM-dd
    required this.amount,
    required this.isIncome, // income -> Debit; expense -> Credit
    required this.details,
  });

  final String date;
  final double amount;
  final bool isIncome;
  final String details;
}
