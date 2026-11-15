import {
  indianDate,
  money,
  parseFederalCells,
  type PdfCell,
} from "./parser.ts";
function check(ok: boolean, message: string) {
  if (!ok) throw new Error(message);
}
Deno.test("India date parsing rejects invalid days and uses day/month order", () => {
  check(indianDate("12/11/2026") === "2026-11-12", "day/month");
  check(indianDate("13-Nov-2026") === "2026-11-13", "named month");
  check(indianDate("31/02/2026") === null, "invalid day");
  check(indianDate("01-01-26") === "2026-01-01", "short year");
});
Deno.test("Money parser uses paise and rejects ambiguous strings", () => {
  check(money("1,23,456.78") === 12345678, "Indian grouping");
  check(money("₹ 500.00 Cr") === 50000, "credit suffix");
  check(money("123abc") === null, "invalid input");
});
Deno.test("PDF columns keep withdrawals and deposits separate", () => {
  const c = (text: string, x: number, y: number): PdfCell => ({
    text,
    x,
    y,
    page: 1,
  });
  const data = [
    c("Date", 20, 800),
    c("Particulars", 100, 800),
    c("Withdrawal", 320, 800),
    c("Deposit", 410, 800),
    c("Balance", 500, 800),
    c("01/10/2026", 20, 780),
    c("UPI REF123456", 100, 780),
    c("500.00", 320, 780),
    c("9,500.00", 500, 780),
    c("02/10/2026", 20, 760),
    c("NEFT ABC123456", 100, 760),
    c("1,000.00", 410, 760),
    c("10,500.00", 500, 760),
  ];
  const result = parseFederalCells(data);
  check(result.lines.length === 2, "two lines");
  check(result.lines[0].transaction_type === "expense", "debit");
  check(result.lines[1].transaction_type === "income", "credit");
  check(result.lines[1].amount === "1000.00", "amount");
  check(result.lines[0].reference === "REF123456", "reference retained");
  check(result.warnings.length === 0, "clean rows");
});
Deno.test("Unrecognised columns and ambiguous debit/credit rows require review", () => {
  const c = (text: string, x: number, y: number): PdfCell => ({
    text,
    x,
    y,
    page: 1,
  });
  const result = parseFederalCells([
    c("01/10/2026", 20, 780),
    c("500.00", 320, 780),
  ]);
  check(
    result.lines.length === 0 && result.warnings.length > 0,
    "do not guess direction",
  );
});

Deno.test("Federal wrapped posting dates and right-aligned small withdrawals stay in their columns", () => {
  const cells: PdfCell[] = [
    { text: "Date", x: 55, y: 800, page: 1 },
    { text: "Value Date", x: 98, y: 800, page: 1 },
    { text: "Withdrawals", x: 400, y: 800, page: 1 },
    { text: "Deposits", x: 453, y: 800, page: 1 },
    { text: "Balance", x: 510, y: 800, page: 1 },
    { text: "09-AUG-", x: 55, y: 780, page: 1 },
    { text: "2026", x: 68, y: 771, page: 1 },
    { text: "10-AUG-26", x: 98, y: 780, page: 1 },
    { text: "Synthetic deposit", x: 160, y: 780, page: 1 },
    { text: "9000", x: 468, y: 780, page: 1 },
    { text: "31900.37", x: 526, y: 780, page: 1 },
    { text: "10-AUG-", x: 55, y: 750, page: 1 },
    { text: "2026", x: 68, y: 741, page: 1 },
    { text: "10-AUG-26", x: 98, y: 750, page: 1 },
    { text: "Synthetic charge", x: 160, y: 750, page: 1 },
    { text: "10.00", x: 438, y: 750, page: 1 },
    { text: "31890.37", x: 526, y: 750, page: 1 },
  ];
  const result = parseFederalCells(cells);
  if (
    result.lines.length !== 2 || result.warnings.length ||
    result.lines[0].date !== "2026-08-09" ||
    result.lines[0].transaction_type !== "income" ||
    result.lines[1].transaction_type !== "expense" ||
    result.lines[1].amount !== "10.00" ||
    result.lines[0].description !== "Synthetic deposit"
  ) throw new Error("Federal table layout regression");
});
