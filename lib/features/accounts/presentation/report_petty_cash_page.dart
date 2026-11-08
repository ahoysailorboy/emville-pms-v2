// lib/features/accounts/presentation/report_petty_cash_page.dart
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

// ✅ Responsive helper (same convention as other pages)
import 'package:emville_pms/responsive/responsive.dart';

class ReportPettyCashPage extends StatefulWidget {
  const ReportPettyCashPage({super.key});

  @override
  State<ReportPettyCashPage> createState() => _ReportPettyCashPageState();
}

enum _RangeMode { monthly, yearly, custom }

enum _TxStatusFilter { approved, pending, all }

enum _ExportKind { excel, pdf }

class _ReportPettyCashPageState extends State<ReportPettyCashPage> {
  final _sb = Supabase.instance.client;

  // Emville theme
  static const Color _green = Color(0xFF103329);
  static const Color _gold = Color(0xFFD9A633);

  // Controls
  _RangeMode _mode = _RangeMode.monthly;
  _TxStatusFilter _status = _TxStatusFilter.approved;
  _ExportKind _export = _ExportKind.excel;

  // Monthly
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Yearly (Financial year: Apr 1 → Mar 31)
  int _fyStartYear = _defaultFyStart();

  // Custom
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
        final s = DateTime(_month.year, _month.month, 1);
        return DateTime(s.year, s.month + 1, 0);
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
  final _dfSql = DateFormat('yyyy-MM-dd');

  Future<_ReportData> _fetchData() async {
    final startStr = _dfSql.format(_rangeStart);
    final endStr = _dfSql.format(_rangeEnd);

    // Opening balance from rows BEFORE start date (respect status filter)
    final opening = await _openingBalanceBefore(startStr);

    // In-range rows
    var q = _sb.from('petty_cash_ledger').select(
          'date, amount, transaction_type, remarks, transaction_status',
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
            details: (m['remarks'] as String?)?.trim() ?? '',
          ),
        )
        .toList();

    return _ReportData(openingBalance: opening, items: items);
  }

  Future<double> _openingBalanceBefore(String startDate) async {
    var q = _sb
            .from('petty_cash_ledger')
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
    final sheet = excel['Petty Cash'];
    final dfOut = DateFormat('dd-MM-yyyy');

    String fmtDate(String s) {
      if (s.isEmpty) return '';
      try {
        return dfOut.format(DateTime.parse(s));
      } catch (_) {
        return s;
      }
    }

    int row = 0;

    _writeRow(sheet, row++, <dynamic>['Petty Cash Account Report']);
    _writeRow(sheet, row++, <dynamic>[_rangeTitle()]);
    _writeRow(sheet, row++, <dynamic>['Status: ${_status.name}']);
    row++;

    _writeRow(sheet, row++, <dynamic>[
      'Date',
      'Details',
      'Debit (₹)', // income
      'Credit (₹)', // expense
      'Balance (₹)',
    ]);

    double running = data.openingBalance;

    // Opening
    _writeRow(sheet, row++, <dynamic>[
      dfOut.format(_rangeStart),
      'Opening Balance',
      '',
      '',
      running,
    ]);

    // Transactions
    for (final r in data.items) {
      running += r.isIncome ? r.amount : -r.amount;
      _writeRow(sheet, row++, <dynamic>[
        fmtDate(r.date),
        r.details,
        r.isIncome ? r.amount : '',
        r.isIncome ? '' : r.amount,
        running,
      ]);
    }

    // Closing
    row++;
    _writeRow(sheet, row++, <dynamic>[
      dfOut.format(_rangeEnd),
      'Closing Balance',
      '',
      '',
      running,
    ]);

    // Totals (sum of debits/credits for the period)
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
        'petty_cash_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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
  // PDF EXPORT (with header/footer)
  // ----------------------------
  Future<void> _exportPdf(_ReportData data) async {
    // Fonts
    final roboto = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
    );
    final robotoItalic = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Roboto-Italic.ttf'),
    );

    // Logo
    final logoBytes = await rootBundle.load('assets/images/app_icon.png');
    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());

    // Brand colors
    final brandGreen = const PdfColor(0.06, 0.20, 0.15); // ~ #103329
    final brandGold = const PdfColor(0.85, 0.65, 0.20); // ~ #D9A633

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: roboto,
        bold: roboto,
        italic: robotoItalic,
      ),
    );

    final reportTitle = 'Petty Cash Account Report';
    final subTitle = _rangeTitle();
    final statusLine = 'Status: ${_status.name}';
    final dfOut = DateFormat('dd-MM-yyyy');

    // Build table rows
    final headers = <String>[
      'Date',
      'Details',
      'Debit (₹)',
      'Credit (₹)',
      'Balance (₹)',
    ];

    double running = data.openingBalance;
    final bodyRows = <List<String>>[];

    // Opening
    bodyRows.add([
      dfOut.format(_rangeStart),
      'Opening Balance',
      '',
      '',
      running.toStringAsFixed(2),
    ]);

    double totalIncome = 0, totalExpense = 0;

    // Transactions (oldest first)
    for (final r in data.items) {
      if (r.isIncome) {
        running += r.amount;
        totalIncome += r.amount;
      } else {
        running -= r.amount;
        totalExpense += r.amount;
      }
      bodyRows.add([
        (r.date.isEmpty ? '' : dfOut.format(DateTime.parse(r.date))),
        r.details,
        r.isIncome ? r.amount.toStringAsFixed(2) : '',
        r.isIncome ? '' : r.amount.toStringAsFixed(2),
        running.toStringAsFixed(2),
      ]);
    }

    // Closing
    bodyRows.add(['', '', '', '', '']);
    bodyRows.add([
      dfOut.format(_rangeEnd),
      'Closing Balance',
      '',
      '',
      running.toStringAsFixed(2),
    ]);

    // Blank spacer rows
    bodyRows.add(['', '', '', '', '']);
    bodyRows.add(['', '', '', '', '']);

    // Totals
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
        header: (context) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: pw.BoxDecoration(color: brandGreen),
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
                    "Emville Homestay",
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
              0: const pw.FixedColumnWidth(72), // Date
              1: const pw.FlexColumnWidth(3), // Details
              2: const pw.FixedColumnWidth(70), // Debit
              3: const pw.FixedColumnWidth(70), // Credit
              4: const pw.FixedColumnWidth(80), // Balance
            },
          ),
        ],
      ),
    );

    final dir = await _preferredSaveDir();
    final fname =
        'petty_cash_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${dir.path}/$fname');
    await file.writeAsBytes(await pdf.save(), flush: true);

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved: ${file.path}')));
      await OpenFilex.open(file.path);
    }
  }

  // ----------------------------
  // UI HELPERS
  // ----------------------------
  String _rangeTitle() {
    switch (_mode) {
      case _RangeMode.monthly:
        return 'Month: ${DateFormat('MMMM yyyy').format(_month)}';
      case _RangeMode.yearly:
        return 'Financial Year: $_fyStartYear–${_fyStartYear + 1}';
      case _RangeMode.custom:
        final d = DateFormat('dd-MM-yyyy');
        return 'From ${d.format(_rangeStart)} to ${d.format(_rangeEnd)}';
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

  Future<Directory> _ensureDir() => _preferredSaveDir();

  // ----------------------------
  // BUILD (Emville layout only)
  // ----------------------------
  @override
  Widget build(BuildContext context) {
    final rs = ResponsiveSize.of(context);

    final fyItems = List.generate(12, (i) {
      final y = _defaultFyStart() - 6 + i;
      return DropdownMenuItem(
        value: y,
        child: Text(
          '$y–${y + 1}',
          style: TextStyle(color: _green, fontSize: rs.font(14)),
        ),
      );
    });

    // Brand-styled segmented buttons
    final segStyle = ButtonStyle(
      side: WidgetStateProperty.all(
        const BorderSide(color: _green, width: 1.2),
      ),
      foregroundColor: WidgetStateProperty.resolveWith<Color>((_) => _green),
      backgroundColor: WidgetStateProperty.resolveWith<Color>(
        (states) => states.contains(WidgetState.selected)
            ? _gold.withValues(alpha: 0.18)
            : Colors.white,
      ),
      overlayColor: WidgetStateProperty.all(_green.withValues(alpha: 0.06)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _green,
        iconTheme: const IconThemeData(color: _gold),
        title: Text(
          'Petty Cash Account Report',
          style: TextStyle(
            color: _gold,
            fontWeight: FontWeight.bold,
            fontSize: rs.font(18),
          ),
        ),
      ),
      body: SafeArea(
        minimum: EdgeInsets.all(rs.space(16)),
        child: ListView(
          children: [
            Text(
              'Report Range',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _green,
                fontSize: rs.font(14),
              ),
            ),
            SizedBox(height: rs.space(8)),
            SegmentedButton<_RangeMode>(
              style: segStyle,
              segments: const [
                ButtonSegment(
                  value: _RangeMode.monthly,
                  label: Text('Monthly'),
                ),
                ButtonSegment(
                  value: _RangeMode.yearly,
                  label: Text('Yearly (FY)'),
                ),
                ButtonSegment(value: _RangeMode.custom, label: Text('From–To')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            SizedBox(height: rs.space(12)),
            if (_mode == _RangeMode.monthly)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Month',
                  style: TextStyle(
                    color: _green,
                    fontWeight: FontWeight.w600,
                    fontSize: rs.font(14),
                  ),
                ),
                subtitle: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  style: TextStyle(color: _green, fontSize: rs.font(14)),
                ),
                trailing: IconButton(
                  icon:
                      Icon(Icons.date_range, color: _green, size: rs.icon(20)),
                  onPressed: _pickMonth,
                ),
              ),
            if (_mode == _RangeMode.yearly)
              Row(
                children: [
                  Text(
                    'Financial Year Start: ',
                    style: TextStyle(
                      color: _green,
                      fontWeight: FontWeight.w600,
                      fontSize: rs.font(14),
                    ),
                  ),
                  SizedBox(width: rs.space(12)),
                  DropdownButton<int>(
                    value: _fyStartYear,
                    dropdownColor: Colors.white,
                    items: fyItems,
                    onChanged: (v) => setState(() => _fyStartYear = v!),
                  ),
                ],
              ),
            if (_mode == _RangeMode.custom)
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'From',
                        style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w600,
                          fontSize: rs.font(14),
                        ),
                      ),
                      subtitle: Text(
                        DateFormat('dd MMM yyyy').format(_from),
                        style: TextStyle(color: _green, fontSize: rs.font(14)),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.date_range,
                            color: _green, size: rs.icon(20)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _from,
                            firstDate: DateTime(2020, 1, 1),
                            lastDate: DateTime.now(),
                            helpText: 'From date',
                          );
                          if (picked != null) setState(() => _from = picked);
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: rs.space(8)),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'To',
                        style: TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w600,
                          fontSize: rs.font(14),
                        ),
                      ),
                      subtitle: Text(
                        DateFormat('dd MMM yyyy').format(_to),
                        style: TextStyle(color: _green, fontSize: rs.font(14)),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.date_range,
                            color: _green, size: rs.icon(20)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _to,
                            firstDate: DateTime(2020, 1, 1),
                            lastDate: DateTime.now(),
                            helpText: 'To date',
                          );
                          if (picked != null) setState(() => _to = picked);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            Divider(height: rs.space(24), color: _green.withValues(alpha: 0.2)),
            Text(
              'Transaction Status',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _green,
                fontSize: rs.font(14),
              ),
            ),
            SizedBox(height: rs.space(8)),
            SegmentedButton<_TxStatusFilter>(
              style: segStyle,
              segments: const [
                ButtonSegment(
                  value: _TxStatusFilter.approved,
                  label: Text('Approved'),
                ),
                ButtonSegment(
                  value: _TxStatusFilter.pending,
                  label: Text('Pending'),
                ),
                ButtonSegment(value: _TxStatusFilter.all, label: Text('All')),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            Divider(height: rs.space(24), color: _green.withValues(alpha: 0.2)),
            Text(
              'File Type',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _green,
                fontSize: rs.font(14),
              ),
            ),
            SizedBox(height: rs.space(8)),
            SegmentedButton<_ExportKind>(
              style: segStyle,
              segments: const [
                ButtonSegment(value: _ExportKind.excel, label: Text('Excel')),
                ButtonSegment(value: _ExportKind.pdf, label: Text('PDF')),
              ],
              selected: {_export},
              onSelectionChanged: (s) => setState(() => _export = s.first),
            ),
            SizedBox(height: rs.space(24)),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: _gold,
                padding: EdgeInsets.symmetric(
                  horizontal: rs.space(16),
                  vertical: rs.space(14),
                ),
                textStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: rs.font(14),
                ),
              ),
              icon: Icon(Icons.insert_drive_file_outlined, size: rs.icon(20)),
              label: const Text('Generate'),
              onPressed: () async {
                try {
                  await _ensureDir();
                  final data = await _fetchData();
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
            ),
          ],
        ),
      ),
    );
  }
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
