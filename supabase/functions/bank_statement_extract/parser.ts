export type PdfCell = { text: string; x: number; y: number; page: number };
export type BankLine = {
  date: string;
  amount: string;
  transaction_type: "income" | "expense";
  description: string;
  reference: string;
};
export function money(raw: string): number | null {
  const value = raw.replace(/[₹,\s]/g, "").replace(/(?:CR|DR)$/i, "");
  if (!/^\d+(?:\.\d{1,2})?$/.test(value)) return null;
  const [r, p = ""] = value.split(".");
  const cents = Number(r) * 100 + Number(p.padEnd(2, "0"));
  return Number.isSafeInteger(cents) ? cents : null;
}
export function indianDate(raw: string): string | null {
  const value = raw.trim();
  const numeric = value.match(/^(\d{1,2})[\/.-](\d{1,2})[\/.-](\d{2}|\d{4})$/);
  const named = value.match(/^(\d{1,2})[ -]([a-z]{3,9})[ -](\d{2}|\d{4})$/i);
  if (!numeric && !named) return null;
  const d = Number((numeric ?? named)![1]);
  const month = numeric ? Number(numeric[2]) : [
    "jan",
    "feb",
    "mar",
    "apr",
    "may",
    "jun",
    "jul",
    "aug",
    "sep",
    "oct",
    "nov",
    "dec",
  ].indexOf(named![2].slice(0, 3).toLowerCase()) + 1;
  const y = (numeric ?? named)![3];
  const year = y.length === 2 ? 2000 + Number(y) : Number(y);
  const dt = new Date(Date.UTC(year, month - 1, d));
  return month > 0 && dt.getUTCFullYear() === year &&
      dt.getUTCMonth() === month - 1 && dt.getUTCDate() === d
    ? dt.toISOString().slice(0, 10)
    : null;
}
// Preserve PDF column coordinates; do not infer a debit/credit from prose.
export function parseFederalCells(cells: PdfCell[]) {
  // Federal Bank wraps the posting year beneath DD-MMM-. Value date is
  // a separate column and must never replace the posting date.
  const federalLayout = cells.some((c) => /^value date$/i.test(c.text.trim()));
  const normalized = cells.map((c) => {
    if (!federalLayout || c.x >= 90 || !/^\d{1,2}-[a-z]{3}-$/i.test(c.text)) {
      return c;
    }
    const year = cells.find((y) =>
      y.page === c.page && /^\d{4}$/.test(y.text) && Math.abs(y.x - c.x) < 25 &&
      c.y - y.y > 0 && c.y - y.y < 15
    );
    return year ? { ...c, text: c.text + year.text } : c;
  });
  const rows: { page: number; y: number; cells: PdfCell[] }[] = [];
  for (
    const cell of [...normalized].sort((a, b) =>
      a.page - b.page || b.y - a.y || a.x - b.x
    )
  ) {
    let row = rows.at(-1);
    if (!row || row.page !== cell.page || Math.abs(row.y - cell.y) > 3) {
      row = { page: cell.page, y: cell.y, cells: [] };
      rows.push(row);
    }
    row.cells.push(cell);
  }
  let debit: number | null = null,
    credit: number | null = null,
    balance: number | null = null;
  const lines: BankLine[] = [];
  const warnings: string[] = [];
  let previous: BankLine | undefined;
  for (const row of rows) {
    const cols = row.cells.sort((a, b) => a.x - b.x);
    const dateCell = cols.find((c) =>
      c.x < (federalLayout ? 90 : 180) && indianDate(c.text) !== null
    );
    for (const c of dateCell ? [] : cols) {
      if (/^(?:withdrawals?|debits?)(?:\s*\(.*\))?$/i.test(c.text.trim())) {
        debit = c.x;
      }
      if (/^(?:deposits?|credits?)(?:\s*\(.*\))?$/i.test(c.text.trim())) {
        credit = c.x;
      }
      if (/^balance(?:\s*\(.*\))?$/i.test(c.text.trim())) balance = c.x;
    }
    if (!dateCell) {
      if (previous && debit !== null) {
        const continuation = cols.filter((c) =>
          c.x > (federalLayout ? 140 : 70) &&
          c.x < (federalLayout ? 325 : Math.min(debit!, credit ?? debit!) - 10)
        ).map((c) => c.text).join(" ").trim();
        if (
          continuation &&
          !/date|particulars|description|statement|page|opening|closing|balance|federal|debit|credit/i
            .test(continuation)
        ) previous.description += " " + continuation;
      }
      continue;
    }
    if (debit === null || credit === null) {
      warnings.push(
        `Page ${row.page}: debit/credit column headings were not recognised. Review or enter transactions manually.`,
      );
      continue;
    }
    const numbers = cols.map((c) => ({ ...c, cents: money(c.text) })).filter(
      (c) => c.cents !== null && c.x > Math.min(debit!, credit!) - 15,
    );
    function columnAt(x: number) {
      return numbers.filter((c) => {
        if (federalLayout) {
          // Amounts are right aligned; headings mark column starts rather
          // than numeric baselines. Nearest-heading matching is unsafe.
          const starts = [
            debit!,
            credit!,
            ...(balance === null ? [] : [balance]),
          ].sort((a, b) => a - b);
          return c.x >= x - 10 &&
            c.x < ((starts.find((v) => v > x) ?? Infinity) - 10);
        }
        const centres = [
          debit!,
          credit!,
          ...(balance === null ? [] : [balance]),
        ];
        return centres.reduce((a, b) =>
          Math.abs(c.x - a) <= Math.abs(c.x - b) ? a : b
        ) === x;
      }).map((c) => c.cents!).filter((v) => v > 0);
    }
    const debits = columnAt(debit), credits = columnAt(credit);
    if (debits.length + credits.length !== 1) {
      warnings.push(
        `Page ${row.page}, ${dateCell.text}: amount columns need review.`,
      );
      continue;
    }
    const type = credits.length ? "income" : "expense",
      amount = credits[0] ?? debits[0];
    const description = cols.filter((c) =>
      c !== dateCell && !indianDate(c.text) &&
      c.x >= (federalLayout ? 140 : 0) &&
      c.x < (federalLayout ? 325 : Math.min(debit!, credit!) - 10)
    ).map((c) => c.text).join(" ").trim();
    let reference = description.match(
      /(?:UTR|REF(?:ERENCE)?|UPI|NEFT|IMPS)[\s:/-]*([A-Z0-9]{6,})/i,
    )?.[1] ?? "";
    if (!/\d/.test(reference)) reference = "";
    previous = {
      date: indianDate(dateCell.text)!,
      amount: (amount / 100).toFixed(2),
      transaction_type: type,
      description: description || "Bank transaction",
      reference,
    };
    lines.push(previous);
  }
  return {
    lines,
    warnings: [...new Set(warnings)],
    text: rows.map((r) => r.cells.map((c) => c.text).join(" ")).join("\n"),
  };
}
