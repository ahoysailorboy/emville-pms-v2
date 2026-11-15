// Isolated PostgreSQL integration tests. Never connect to production.
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
const { PGlite } = await import(
  process.env.PGLITE_MODULE || "@electric-sql/pglite"
);
const db = new PGlite();
const owner = "00000000-0000-4000-8000-000000000001",
  admin = "00000000-0000-4000-8000-000000000002",
  worker = "00000000-0000-4000-8000-000000000003";
await db.exec(
  `create role anon;create role authenticated;create role service_role;
create schema auth;create schema storage;create schema cron;
create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('test.uid',true),'')::uuid$$;
grant usage on schema auth,public,storage to authenticated;
create table users(uid uuid primary key,full_name text,email text,role text,is_authorized boolean);
create function is_authorized_uid(u uuid) returns boolean language sql stable security definer as $$select coalesce((select is_authorized from users where uid=u),false)$$;
create type main_trx_type as enum('income','expense');create type main_trx_status as enum('pending','approved');create type main_payment_mode as enum('bank_transfer','upi','card','cash');
create table main_ledger(id uuid primary key default gen_random_uuid(),date date not null,amount numeric(14,2),transaction_type main_trx_type,transaction_status main_trx_status,created_by text,creator_uuid uuid,approved_by text,payee_payer_name text,remarks text,payment_mode main_payment_mode,account_balance numeric,created_time timestamptz default now());
create table main_ledger_balance(id boolean primary key,ledger_balance numeric,approved_balance numeric);insert into main_ledger_balance values(true,0,0);
grant select on main_ledger,main_ledger_balance to authenticated;
create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid default gen_random_uuid(),bucket_id text,name text);alter table storage.objects enable row level security;grant select,insert,delete on storage.objects to authenticated;
create function storage.foldername(text) returns text[] language sql immutable as $$select string_to_array($1,'/')$$;
create table cron.job(jobname text primary key,schedule text,active boolean default true);
create function cron.schedule(n text,s text,q text) returns bigint language plpgsql as $$begin insert into cron.job(jobname,schedule) values(n,s) on conflict(jobname) do update set schedule=excluded.schedule;return 1;end$$;
create table work_reminders(id uuid default gen_random_uuid(),title text,description text,created_by uuid,assigned_to uuid,due_at timestamptz,status text default 'open',revision integer default 0,updated_at timestamptz default now());
grant select on work_reminders to authenticated;
create table task_notification_queue(id uuid default gen_random_uuid(),recipient uuid,title text,message text);
`,
);
for (
  const [id, name, role] of [[owner, "Owner", "owner"], [
    admin,
    "Admin",
    "admin",
  ], [worker, "Worker", "user"]]
) {
  await db.query("insert into users values($1,$2,$3,$4,true)", [
    id,
    name,
    `${name}@example.com`,
    role,
  ]);
}
await db.exec(`
create function main_ai() returns trigger language plpgsql as $$begin update main_ledger_balance set ledger_balance=ledger_balance+case when new.transaction_type='income' then new.amount else -new.amount end;return new;end$$;
create function main_au() returns trigger language plpgsql as $$begin if old.transaction_status<>'approved' and new.transaction_status='approved' then update main_ledger_balance set approved_balance=approved_balance+case when new.transaction_type='income' then new.amount else -new.amount end;end if;return new;end$$;
create trigger main_ai after insert on main_ledger for each row execute function main_ai();create trigger main_au after update on main_ledger for each row execute function main_au();
`);
await db.exec(
  await readFile(
    new URL(
      "../migrations/20261115100000_bank_reconciliation.sql",
      import.meta.url,
    ),
    "utf8",
  ),
);
await db.exec(await readFile(new URL('../migrations/20261115100100_bank_reconciliation_permissions.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../migrations/20261115100200_bank_reconciliation_posting.sql',import.meta.url),'utf8'));
const query = async (s, p = []) => (await db.query(s, p)).rows;
assert.equal((await query("select has_function_privilege('anon','public.queue_monthly_bank_reconciliation_reminders()','execute') as allowed"))[0].allowed,false);
const onReminderDay = Number(
  (await query(
    "select extract(day from now() at time zone 'Asia/Kolkata') as d",
  ))[0].d,
) >= 2;
await query("select queue_monthly_bank_reconciliation_reminders()");
await query("select queue_monthly_bank_reconciliation_reminders()");
if (onReminderDay) {
  assert.equal(
    (await query("select count(*)::int as n from work_reminders"))[0].n,
    2,
  );
  assert.equal(
    (await query("select count(*)::int as n from task_notification_queue"))[0]
      .n,
    2,
  );
  assert.equal(
    (await query(
      "select count(*)::int as n from work_reminders where assigned_to=$1",
      [worker],
    ))[0].n,
    0,
  );
}

const as = async (uid) => {
  await db.exec("reset role");
  await db.query("select set_config('test.uid',$1,false)", [uid]);
  await db.exec("set role authenticated");
};
const rejected = async (fn) => {
  await assert.rejects(fn);
};
const month = (await query(
  "select (date_trunc('month',current_date)-interval '1 month')::date::text as month",
))[0].month;
const date = (n) => month.slice(0, 8) + String(n).padStart(2, "0");
const id = "10000000-0000-4000-8000-000000000001", path = `${owner}/${id}.pdf`;
await db.query(
  "insert into storage.objects(bucket_id,name) values('bank-statements',$1)",
  [path],
);
async function ledger(
  n,
  amount,
  type,
  ref,
  status = "approved",
  mode = "bank_transfer",
) {
  const [{ id }] = await query(
    "insert into main_ledger(date,amount,transaction_type,transaction_status,created_by,creator_uuid,remarks,payment_mode) values($1,$2,$3,'pending','Owner',$4,$5,$6) returning id",
    [date(n), amount, type, owner, ref, mode],
  );
  if (status === "approved") {
    await query(
      "update main_ledger set transaction_status='approved' where id=$1",
      [id],
    );
  }
  return id;
}
const income = await ledger(2, 10000, "income", "UTR INCOME100");
await ledger(3, 500, "expense", "UPI EXPENSE200");
const ambiguous = await ledger(6, 600, "expense", "General expense");
const adjusted = await ledger(7, 1000, "income", "UTR ABCDEF123");
const pending = await ledger(8, 100, "expense", "UPI PENDING100", "pending");
const extra = await ledger(9, 75, "expense", "Bank debit not on statement");
const lines = [
  {
    date: date(2),
    amount: "10000.00",
    transaction_type: "income",
    description: "Customer payment",
    reference: "INCOME100",
  },
  {
    date: date(3),
    amount: "500.00",
    transaction_type: "expense",
    description: "Supplier payment",
    reference: "EXPENSE200",
  },
  {
    date: date(4),
    amount: "250.00",
    transaction_type: "expense",
    description: "Bank fee",
    reference: "",
  },
  {
    date: date(6),
    amount: "600.00",
    transaction_type: "expense",
    description: "Ambiguous one",
    reference: "",
  },
  {
    date: date(6),
    amount: "600.00",
    transaction_type: "expense",
    description: "Ambiguous two",
    reference: "",
  },
  {
    date: date(7),
    amount: "800.00",
    transaction_type: "income",
    description: "Short payment",
    reference: "ABCDEF123",
  },
  {
    date: date(8),
    amount: "100.00",
    transaction_type: "expense",
    description: "Pending ledger payment",
    reference: "PENDING100",
  },
];
await as(worker);
assert.equal((await query("select * from storage.objects")).length, 0);
await rejected(() =>
  query("select create_bank_reconciliation($1,$2,$3,$4,2000,10750,$5::jsonb)", [
    id,
    month,
    path,
    "a".repeat(64),
    JSON.stringify(lines),
  ])
);
await as(owner);
await rejected(() =>
  query("select create_bank_reconciliation($1,$2,$3,$4,2000,999,$5::jsonb)", [
    id,
    month,
    path,
    "a".repeat(64),
    JSON.stringify(lines),
  ])
);
await query(
  "select create_bank_reconciliation($1,$2,$3,$4,2000,10750,$5::jsonb)",
  [id, month, path, "a".repeat(64), JSON.stringify(lines)],
);
await query("select compare_bank_reconciliation($1)", [id]);
const current = await query(
  "select * from bank_statement_lines where reconciliation_id=$1 order by line_number",
  [id],
);
assert.deepEqual(current.map((r) => r.state), [
  "matched",
  "matched",
  "unmatched",
  "review",
  "review",
  "review",
  "pending_approval",
]);
let proposals = await query(
  "select * from bank_reconciliation_proposals order by kind",
);
assert.equal(proposals.length, 2);
assert.equal(proposals.find((p) => p.kind === "adjustment").amount, "200.00");
await rejected(() =>
  query("select set_bank_reconciliation_status($1,true)", [id])
);
await as(worker);
assert.equal((await query("select * from bank_reconciliations")).length, 0);
await rejected(() =>
  query("select approve_bank_proposal($1,$2,$3)", [
    proposals[0].id,
    "Not allowed",
    "Bank",
  ])
);
await as(admin);
const missing = proposals.find((p) => p.kind === "missing");
let before = (await query("select * from main_ledger_balance"))[0];
const [{ newid }] = await query(
  "select approve_bank_proposal($1,$2,$3) as newid",
  [missing.id, "Reviewed bank service charge", "Federal Bank"],
);
let after = (await query("select * from main_ledger_balance"))[0];
assert.equal(Number(after.ledger_balance), Number(before.ledger_balance) - 250);
assert.equal(
  Number(after.approved_balance),
  Number(before.approved_balance) - 250,
);
assert.equal(
  (await query("select approve_bank_proposal($1,$2,$3) as newid", [
    missing.id,
    "Retry",
    "Federal Bank",
  ]))[0].newid,
  newid,
);
assert.equal(
  (await query("select count(*)::int as n from main_ledger where id=$1", [
    newid,
  ]))[0].n,
  1,
);
const adjustment = proposals.find((p) => p.kind === "adjustment");
await query("select approve_bank_proposal($1,$2,$3)", [
  adjustment.id,
  "Confirmed 200 short payment",
  "Customer",
]);
assert.equal(
  Number(
    (await query(
      "select sum(case when l.transaction_type='income' then l.amount else -l.amount end) as n from bank_reconciliation_links k join main_ledger l on l.id=k.ledger_id where k.line_id=$1",
      [adjustment.line_id],
    ))[0].n,
  ),
  800,
);
for (
  const line of current.filter((r) =>
    r.state === "review" && r.description.startsWith("Ambiguous")
  )
) {
  await query("select resolve_bank_line($1,$2,$3)", [
    line.id,
    "timing",
    "Requires bank confirmation",
  ]);
}
await db.exec("reset role");
await query(
  "update main_ledger set transaction_status='approved' where id=$1",
  [pending],
);
await as(admin);
await query("select compare_bank_reconciliation($1)", [id]);
await query("select review_unmatched_bank_ledger($1,$2,$3,$4)", [
  id,
  ambiguous,
  "timing",
  "Will clear in the next statement",
]);
await query("select review_unmatched_bank_ledger($1,$2,$3,$4)", [
  id,
  extra,
  "timing",
  "Bank processing delay",
]);
await query("select set_bank_reconciliation_status($1,true)", [id]);
assert.equal(
  (await query("select status from bank_reconciliations where id=$1", [id]))[0]
    .status,
  "completed",
);
await rejected(() => query("select compare_bank_reconciliation($1)", [id]));
await query("select set_bank_reconciliation_status($1,false)", [id]);
await db.exec("reset role");
await query(
  "update main_ledger set remarks='Changed after match' where id=$1",
  [income],
);
await as(owner);
await rejected(() =>
  query("select set_bank_reconciliation_status($1,true)", [id])
);
await rejected(() =>
  query(
    "insert into bank_reconciliation_proposals(line_id,kind,amount,transaction_type,status) values($1,'missing',1,'income','approved')",
    [current[0].id],
  )
);
await query("select review_unmatched_bank_ledger($1,$2,$3,$4)", [
  id,
  extra,
  "duplicate",
  "Confirmed duplicated bank debit",
]);
const reversal = (await query(
  "select * from bank_ledger_reversal_proposals where base_ledger_id=$1",
  [extra],
))[0];
const originalCount =
  (await query("select count(*)::int as n from main_ledger"))[0].n;
const reversed =
  (await query("select approve_bank_ledger_reversal($1,$2) as id", [
    reversal.id,
    "Confirmed duplicate, approved compensation",
  ]))[0].id;
assert.equal(
  (await query("select approve_bank_ledger_reversal($1,$2) as id", [
    reversal.id,
    "Retry",
  ]))[0].id,
  reversed,
);
assert.equal(
  (await query("select count(*)::int as n from main_ledger"))[0].n,
  originalCount + 1,
);
const rb =
  (await query("select * from main_ledger where id=$1", [reversed]))[0];
assert.equal(rb.transaction_type, "income");
assert.equal(Number(rb.amount), 75);
await rejected(() =>
  query("select discard_bank_reconciliation($1,$2)", [
    id,
    "Cannot discard posted corrections",
  ])
);
await db.close();
console.log(
  "Bank reconciliation SQL checks passed: admin access, privacy, balancing, conservative matches, approval, signed adjustments, idempotency, stale-ledger checks and monthly close.",
);
