import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Full brand lockup kept at its original aspect ratio on every report page.
pw.Widget emvillePdfLetterhead(pw.ImageProvider logo) => pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom:
                pw.BorderSide(color: PdfColor.fromInt(0xFF244E3E), width: 1)),
      ),
      child: pw.Center(
          child:
              pw.Image(logo, width: 170, height: 91, fit: pw.BoxFit.contain)),
    );
