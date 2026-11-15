import { PDFDocument, StandardFonts } from "npm:pdf-lib@1.17.1";
import { getDocumentProxy } from "npm:unpdf@1.4.0";
import { parseFederalCells, type PdfCell } from "./parser.ts";
Deno.test("Reads real PDF bytes in the serverless runtime and preserves table amounts", async () => {
  const doc = await PDFDocument.create();
  const page = doc.addPage([600, 850]);
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const draw = (text: string, x: number, y: number) =>
    page.drawText(text, { x, y, size: 9, font });
  draw("Date", 20, 800);
  draw("Particulars", 100, 800);
  draw("Withdrawal", 320, 800);
  draw("Deposit", 410, 800);
  draw("Balance", 500, 800);
  draw("01/10/2026", 20, 780);
  draw("UPI REF123456", 100, 780);
  draw("500.00", 320, 780);
  draw("9500.00", 500, 780);
  draw("02/10/2026", 20, 760);
  draw("NEFT ABC123456", 100, 760);
  draw("1000.00", 410, 760);
  draw("10500.00", 500, 760);
  const pdf = await getDocumentProxy(await doc.save(), {
    isEvalSupported: false,
    maxImageSize: 16777216,
  });
  try {
    const p = await pdf.getPage(1);
    const content = await p.getTextContent();
    const cells: PdfCell[] = [];
    for (const item of content.items) {
      if ("str" in item && item.str.trim()) {
        cells.push({
          text: item.str.trim(),
          x: item.transform[4],
          y: item.transform[5],
          page: 1,
        });
      }
    }
    const result = parseFederalCells(cells);
    if (
      result.lines.length !== 2 || result.lines[0].amount !== "500.00" ||
      result.lines[1].transaction_type !== "income"
    ) throw new Error("PDF extraction did not preserve bank columns");
  } finally {
    await pdf.destroy();
  }
});
