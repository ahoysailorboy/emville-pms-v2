// Run against an isolated PGlite PostgreSQL engine; never connects to Supabase.
// npm install --prefix /tmp/emville-reminder-sql @electric-sql/pglite
// PGLITE_MODULE=/tmp/emville-reminder-sql/node_modules/@electric-sql/pglite/dist/index.js node supabase/tests/reminders.test.mjs
import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";
const { PGlite } = await import(
  process.env.PGLITE_MODULE || "@electric-sql/pglite"
);
const db = new PGlite();
const ids = Object.fromEntries(
  ["owner", "admin", "admin2", "worker", "other"].map((
    r,
    i,
  ) => [r, `00000000-0000-4000-8000-00000000000${i + 1}`]),
);
await db.exec(`
 create role anon; create role authenticated; create role service_role;
 create schema auth;
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
 grant usage on schema public,auth to authenticated;
 create table public.users(uid uuid primary key, full_name text,email text,role text,is_authorized boolean);
 create function public.is_authorized_uid(u uuid) returns boolean language sql stable security definer as $$select coalesce((select is_authorized from public.users where uid=u),false)$$;
 create table public.main_pms_db(job_seq integer primary key,task_name text,remarks text,last_done_date date,next_due_date date,postponed text,user_uuid uuid,updated_date timestamptz);
 insert into main_pms_db values(12,'Deep cleaning','Initial','2025-10-25','2026-04-23','no',null,now());
`);
for (const [name, id] of Object.entries(ids)) {
  await db.query("insert into users values($1,$2,$3,$4,true)", [
    id,
    name,
    `${name}@example.com`,
    name.startsWith("admin") ? "admin" : name === "owner" ? "owner" : "user",
  ]);
}
await db.exec(
  await readFile(
    new URL(
      "../migrations/20261114170000_assigned_reminders.sql",
      import.meta.url,
    ),
    "utf8",
  ),
);
const as = async (role) => {
  await db.exec("reset role");
  await db.query("select set_config('test.uid',$1,false)", [ids[role]]);
  await db.exec("set role authenticated");
};
const rows = async (sql, params = []) => (await db.query(sql, params)).rows;
const expectRejected = async (fn) => {
  let rejected = false;
  try {
    await fn();
  } catch {
    rejected = true;
  }
  assert.ok(rejected, "Expected unauthorized/invalid action to fail");
};
await as("owner");
const [{ id }] = await rows(
  "select create_work_reminder('Clean pool','Check filter',$1,now()+interval '1 day') as id",
  [ids.worker],
);
await db.exec("reset role");
assert.deepEqual(
  (await rows("select recipient from task_notification_queue")).map((r) =>
    r.recipient
  ),
  [ids.worker],
);
await as("other");
assert.equal(
  (await rows("select * from work_reminders")).length,
  0,
  "Unrelated users cannot read tasks",
);
await expectRejected(() =>
  rows("select update_work_reminder($1,0,'completed','Forged',null)", [id])
);
await as("worker");
await expectRejected(() =>
  rows("select update_work_reminder($1,0,'remark','',null)", [id])
);
await rows("select update_work_reminder($1,0,'remark','Filter checked',null)", [
  id,
]);
await db.exec("reset role");
assert.deepEqual(
  new Set(
    (await rows(
      "select recipient from task_notification_queue where reminder_id=$1 and title=$2",
      [id, "Task remark"],
    )).map((r) => r.recipient),
  ),
  new Set([ids.owner, ids.admin, ids.admin2]),
);
await as("worker");
await expectRejected(() =>
  rows("select update_work_reminder($1,0,'completed','Stale write',null)", [id])
);
await expectRejected(() =>
  rows(
    "select update_work_reminder($1,1,'postponed','Need parts',now()-interval '1 day')",
    [id],
  )
);
await rows(
  "select update_work_reminder($1,1,'postponed','Need parts',now()+interval '2 days')",
  [id],
);
await as("admin");
await rows("select update_work_reminder($1,2,'completed','Finished',null)", [
  id,
]);
await db.exec("reset role");
assert.deepEqual(
  new Set(
    (await rows(
      "select recipient from task_notification_queue where reminder_id=$1 and title=$2",
      [id, "Task completed"],
    )).map((r) => r.recipient),
  ),
  new Set([ids.owner, ids.admin2, ids.worker]),
);
assert.equal(
  (await rows("select * from work_reminder_activity where reminder_id=$1", [
    id,
  ])).length,
  4,
);
await as("worker");
await expectRejected(() =>
  rows("select update_work_reminder($1,3,'remark','After completion',null)", [
    id,
  ])
);
await expectRejected(() =>
  rows(
    "insert into work_reminders(title,created_by,assigned_to,due_at) values('Spoof',$1,$2,now())",
    [ids.owner, ids.other],
  )
);
await rows("select add_pms_task_note(12,'Needs cleaning',current_date+2)");
await db.exec("reset role");
assert.equal(
  (await rows(
    "select count(*)::int as n from task_notification_queue where job_seq=12",
  ))[0].n,
  3,
  "One maintenance notification per owner/admin, no duplicates",
);
assert.equal(
  (await rows("select count(*)::int as n from pms_task_notes"))[0].n,
  1,
);
assert.equal(
  (await rows("select postponed from main_pms_db where job_seq=12"))[0]
    .postponed,
  "no",
);
await as("admin");
// Simulate the legacy maintenance completion path after a committed note.
await db.exec("reset role");
await db.query(
  "update main_pms_db set remarks='Completed',last_done_date=current_date where job_seq=12",
);
assert.equal(
  (await rows(
    "select count(*)::int as n from task_notification_queue where job_seq=12",
  ))[0].n,
  5,
  "Completing admin excluded; owner and other admin notified",
);
await db.close();
console.log(
  "Passed reminder SQL checks: RLS, assignees, roles, audit history, stale writes, postponement, completion and maintenance notification routing.",
);
