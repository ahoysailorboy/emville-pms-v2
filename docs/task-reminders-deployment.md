# Assigned tasks and reminders

The new Flutter task features require a Supabase backend deployment. Existing recurring tasks remain in `main_pms_db`; one-off assigned work uses `work_reminders` and an immutable conversation log. Only the creator, assignee and authorized admins/owners can see a reminder. Authorized team members can schedule work for any other authorized member. Updates are restricted to those task participants and admins/owners. Completed tasks cannot be changed. A revision guard rejects simultaneous stale updates.

## Deploy

Both additive migrations have been deployed to project `qcqalhmwawesewphvdrq`:

- `20261114170000_assigned_reminders.sql`: tables, RLS, RPCs and maintenance notification trigger.
- `20261114171000_task_notification_scheduler.sql`: private Vault secret, service-only secret validation and the `emville-task-notification-delivery` cron job (every minute).

`task_notifications` is deployed with `verify_jwt=false`; its handler validates app JWTs and authorization itself, or checks the private scheduler header against the database Vault through a service-role-only RPC. The scheduled command reads the secret from Vault at invocation time. No raw scheduler secret is stored in source code or CLI output. Existing `ONESIGNAL_APP_ID` and `ONESIGNAL_API_KEY` project secrets supply delivery credentials.

For a fresh environment, apply those two migrations in order and deploy the function with `supabase functions deploy task_notifications --project-ref <project-ref> --no-verify-jwt`. Change the scheduler URL when deploying to another project. Do not replay the historical migrations against an existing database.

The migration queues notifications transactionally. The app wakes delivery after changes and on Home load; the scheduler provides independent retries. Delivery uses OneSignal external user IDs already set by the existing login integration. Worker remarks/completion notify every authorized owner/admin except the actor. Admin actions therefore notify other admins and owners. Reminder participants are also notified. Repeated requests use per-recipient UUID idempotency keys. Failed/unsubscribed deliveries retry with backoff; delivery attempts expire after seven days. Legacy recurring maintenance updates are also queued by a database trigger.

## Phone calendars

On Home, the assignee enables phone calendar access once. Assigned future tasks get an event in the default writable calendar, with alerts 15 minutes before and at the due time. A completed task removes its event; postponement updates the existing event instead of creating another. Event IDs are stored locally per account and device.

Reconciliation runs when Home loads, when the app resumes while Home is visible, after returning from task details, or on refresh. A closed app cannot modify another person's native phone calendar remotely. Push notifications and the database assignment are independent of calendar permission. Android needs a writable calendar account; users denying permission can continue using in-app tasks. Phone permission and calendar alerts need device verification before releasing this feature.

## Validation

`flutter test` runs task navigation and form interaction checks with an isolated HTTP backend. `supabase/tests/reminders.test.mjs` executes the migration in PGlite (local PostgreSQL) and checks RLS, spoof prevention, remarks, stale revision rejection, future follow-up validation, audit history and exact owner/admin recipient sets. Its header contains install/run commands. It never connects to Supabase. `deno check --no-config --node-modules-dir=none supabase/functions/task_notifications/index.ts` checks the push handler.

The separately exported release packages were built from committed snapshot `4c9d5e0` and exclude this feature. They retain version `1.2.0` and use build `2026111404`; build `2026111403` is superseded. The main pubspec now records `1.2.0+2026111404` too. The next feature release must increment the build again.

Remote database lint reported no errors in the new reminder functions. It also reported existing unrelated errors in `user_display_name`, `recompute_petty_cash_from`, `notify_admin_new_user` and `ensure_user_row`; these functions were not changed by this work.

The unused `flutter_local_notifications` dependency was removed because it requested Android SDK37, unavailable on this machine. Runtime notifications continue through the existing OneSignal integration.
