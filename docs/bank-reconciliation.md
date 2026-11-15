# Bank reconciliation

Open Accounts → Bank reconciliation as an authorised admin or owner. Upload a Federal Bank PDF for a completed calendar month. Statements are stored in the private `bank-statements` bucket; ordinary users cannot access reconciliation data or PDFs.

Review the extracted dates, descriptions, debit/credit directions and amounts against the original PDF before saving. Opening balance plus credits minus debits must equal closing balance, using integer paise. Scanned or unfamiliar layouts support manual transaction entry. No paid OCR service or bank password is used. Validated against a real four-page Federal Bank statement: 66 transactions and both printed debit/credit totals agree exactly. The parser handles wrapped posting dates separately from value dates and right-aligned amounts. Regression fixtures contain synthetic data only. Upload a statement covering one calendar month; multi-month PDFs must be replaced by a monthly export.

Comparison considers every main-ledger entry. It matches only unambiguous equal signed amounts within three days, and can propose reference-based adjustments. Ambiguous matches require review. Users can link an existing entry, propose a signed adjustment, explicitly propose a separate entry, or document timing, transfer and duplicate exceptions. Entries already reconciled elsewhere cannot be linked again.

Proposals never post automatically. Admins/owners must review and approve them with an approval note. Posting checks for changed ledger data and duplicate candidates, records the approver, updates existing balance triggers, and is idempotent. Duplicate ledger corrections use an approved compensating reversal while preserving the original. Completion checks unresolved bank rows, unmatched ledger rows, pending reversals and stale snapshots. Draft statements can be replaced before any correction is posted; archived PDFs and audit notes remain available.

On the 2nd of each month at 09:00 India time, authorised admins and owners receive a Home reminder and queued push notification to upload the previous month's statement. Reminders are deduplicated and close after upload. Discarding a draft reopens its upload reminder. Push delivery uses the existing notification dispatcher.

Backend: migrations `20261115100000`, `20261115100100`, `20261115100200`; functions `bank_statement_extract` and updated `task_notifications`. Deployment itself does not create or change existing ledger transactions.

Validation: Flutter widget/unit suite; isolated PGlite SQL tests for access, balancing, conservative matching, explicit approval, signed adjustments, reversals, idempotency, stale snapshots and monthly close; six PDF parser/runtime tests. Live SQL lint reported only four pre-existing unrelated functions. No release IPA/APK was rebuilt for this module.
