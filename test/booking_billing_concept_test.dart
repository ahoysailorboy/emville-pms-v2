import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:emville_pms/ui/emville_theme.dart';
import 'package:emville_pms/ui/emville_pdf_letterhead.dart';
import '../design/booking-detail-concept/screens.dart';
import '../design/booking-detail-concept/bill_forms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final entry in {
      'EmvilleSerif': 'assets/fonts/Gelasio.ttf',
      'Roboto': 'assets/fonts/Roboto-Regular.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf'
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  testWidgets('Capture Booking Details and Billing design concepts',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final billing in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Emville.theme,
          home: BookingDesignConcept(billing: billing)));
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        for (final asset in [Emville.pool, Emville.logo]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              '../design/booking-detail-concept/${billing ? 'billing' : 'booking-details'}.png'));
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_DESIGN'));
  testWidgets('Capture bill entry and finalise popup concepts', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final item in <(String, Widget)>[
      ('add-bill', const AddBillDesignConcept()),
      ('finalise-bill-popup', const FinaliseBillDesignConcept())
    ]) {
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Emville.theme,
          home: item.$2));
      await tester.runAsync(() async {
        final context = tester.element(find.byType(MaterialApp));
        for (final asset in [Emville.pool, Emville.logo]) {
          await precacheImage(AssetImage(asset), context);
        }
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (item.$1 == 'finalise-bill-popup') {
        expect(find.byType(Dialog), findsOneWidget);
      }
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('../design/booking-detail-concept/${item.$1}.png'));
      if (item.$1 == 'finalise-bill-popup') {
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
      }
    }
  }, skip: !const bool.fromEnvironment('CAPTURE_DESIGN'));
  test('Report letterhead keeps a fixed logo size across portrait ledger pages',
      () async {
    final logo = pw.MemoryImage(
        (await rootBundle.load(Emville.logo)).buffer.asUint8List());
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf'));
    final doc =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
    for (final format in [PdfPageFormat.a4, PdfPageFormat.a4]) {
      doc.addPage(pw.MultiPage(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(24),
          header: (_) => emvillePdfLetterhead(logo),
          footer: (context) => pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 9))),
          build: (_) => [
                pw.SizedBox(height: 18),
                pw.Text('Main Ledger Report',
                    style: pw.TextStyle(
                        fontSize: 17, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 6),
                pw.Text('Illustrative preview - not a financial statement',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 5),
                pw.Text('Month: November 2026 | Status: approved',
                    style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 16),
                pw.TableHelper.fromTextArray(
                    headers: [
                      'Date',
                      'Details',
                      'Debit (INR)',
                      'Credit (INR)',
                      'Balance (INR)'
                    ],
                    data: [
                      ['01-11-2026', 'Opening balance', '', '', '50,000.00'],
                      [
                        '02-11-2026',
                        'Sample guest payment',
                        '',
                        '12,000.00',
                        '62,000.00'
                      ],
                      [
                        '03-11-2026',
                        'Sample maintenance',
                        '2,500.00',
                        '',
                        '59,500.00'
                      ]
                    ],
                    headerStyle:
                        pw.TextStyle(fontSize: 10, color: PdfColors.white),
                    cellStyle: const pw.TextStyle(fontSize: 10),
                    cellPadding: const pw.EdgeInsets.all(8),
                    headerDecoration: const pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFF244E3E)),
                    border: null),
              ]));
    }
    final bytes = await doc.save();
    expect(bytes.length, greaterThan(10000));
    if (const bool.fromEnvironment('CAPTURE_DESIGN')) {
      await Directory('design/booking-detail-concept').create(recursive: true);
      await File('design/booking-detail-concept/report-letterhead-preview.pdf')
          .writeAsBytes(bytes);
    }
  });
}
