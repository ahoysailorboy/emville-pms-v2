// Isolated PostgreSQL test; never connects to the live database.
// Set PGLITE_MODULE to an installed @electric-sql/pglite module path.
const { PGlite } = await import(
  process.env.PGLITE_MODULE || "@electric-sql/pglite"
);
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
const db = new PGlite();
await db.exec(
  `create table petty_cash_balance(id integer primary key,ledger_balance numeric default 0,approved_balance numeric default 0);insert into petty_cash_balance values(1,4595.37,-4.63);create table petty_cash_ledger(id integer primary key,amount numeric,transaction_type text,transaction_status text);insert into petty_cash_ledger values(1,4595.37,'income','approved');`,
);
await db.exec(
  "CREATE OR REPLACE FUNCTION public.petty_cash_recalc_balances()\n RETURNS void\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO 'public'\nAS $function$\n  with\n  all_rows as (\n    select sum(\n             case when transaction_type = 'income' then amount\n                  when transaction_type = 'expense' then -amount\n                  else 0 end\n           ) as ledger_sum\n    from public.petty_cash_ledger\n  ),\n  approved_rows as (\n    select sum(\n             case when transaction_type = 'income' then amount\n                  when transaction_type = 'expense' then -amount\n                  else 0 end\n           ) as approved_sum\n    from public.petty_cash_ledger\n    where transaction_status = 'approved'\n  )\n  update public.petty_cash_balance b\n  set ledger_balance   = coalesce((select ledger_sum   from all_rows), 0),\n      approved_balance = coalesce((select approved_sum from approved_rows), 0)\n  where b.id = 1;\n$function$\n",
);
const sql = await readFile(
  new URL(
    "../migrations/20261115060000_repair_petty_cash_balances.sql",
    import.meta.url,
  ),
  "utf8",
);
await db.exec(sql);
for (const event of ["insert", "update", "delete"]) {
  await db.exec(
    `create trigger petty_${event} after ${event} on petty_cash_ledger for each row execute function petty_cash_after_${event}()`,
  );
}
const check = async () => {
  const actual = (await db.query("select * from petty_cash_balance")).rows[0];
  const expected = (await db.query(
    `select coalesce(sum(case when transaction_type='income' then amount else -amount end),0) as ledger,coalesce(sum(case when transaction_status='approved' then case when transaction_type='income' then amount else -amount end else 0 end),0) as approved from petty_cash_ledger`,
  )).rows[0];
  assert.equal(Number(actual.ledger_balance), Number(expected.ledger));
  assert.equal(Number(actual.approved_balance), Number(expected.approved));
};
await check();
for (
  const sql of [
    "insert into petty_cash_ledger values(2,4600,'income','approved')",
    "insert into petty_cash_ledger values(3,500,'expense','pending')",
    "update petty_cash_ledger set transaction_status='approved' where id=3",
    "update petty_cash_ledger set amount=750 where id=3",
    "update petty_cash_ledger set transaction_type='income' where id=3",
    "update petty_cash_ledger set transaction_status='pending' where id=3",
    "update petty_cash_ledger set amount=1000 where id=3",
    "delete from petty_cash_ledger where id=3",
    "delete from petty_cash_ledger where id=2",
    "update petty_cash_ledger set transaction_status='approved' where id=1",
    "insert into petty_cash_ledger values(4,100,'expense','approved'),(5,250,'income','pending')",
    "update petty_cash_ledger set amount=amount+10 where id in (4,5)",
    "delete from petty_cash_ledger where id in (4,5)",
  ]
) {
  await db.exec(sql);
  await check();
}
await db.close();
console.log(
  "Passed reconciliation and 13 insert/update/approval/reversal/type-change/delete checks.",
);
