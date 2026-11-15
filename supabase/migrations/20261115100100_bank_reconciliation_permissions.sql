BEGIN;
-- Supabase default privileges can grant functions directly to anon/authenticated.
-- Remove those explicit grants as well as PUBLIC before assigning the intended roles.
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('create_bank_reconciliation','discard_bank_reconciliation','compare_bank_reconciliation','propose_distinct_bank_entry','resolve_bank_line','approve_bank_proposal','set_bank_reconciliation_status','review_unmatched_bank_ledger','approve_bank_ledger_reversal') LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC,anon,authenticated',f.sig);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.queue_monthly_bank_reconciliation_reminders() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.queue_monthly_bank_reconciliation_reminders() TO service_role;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['bank_reconciliations','bank_statement_lines','bank_reconciliation_links','bank_reconciliation_proposals','bank_reconciliation_notes','bank_ledger_reviews','bank_ledger_reversal_proposals'] LOOP
  IF NOT EXISTS(SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname=t AND c.relrowsecurity) THEN RAISE EXCEPTION 'Bank statement privacy check failed for %',t; END IF;
 END LOOP;
 IF NOT EXISTS(SELECT 1 FROM storage.buckets WHERE id='bank-statements' AND public=false) THEN RAISE EXCEPTION 'Bank statements bucket must be private'; END IF;
 IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='emville-monthly-bank-reconciliation' AND active AND schedule='30 3 2 * *') THEN RAISE EXCEPTION 'Monthly bank reminder schedule missing'; END IF;
 IF coalesce(current_setting('cron.timezone',true),'GMT') NOT IN ('GMT','UTC','Etc/UTC') THEN RAISE EXCEPTION 'Review cron timezone before enabling the 09:00 India reminder'; END IF;
 RAISE NOTICE 'Bank reconciliation privacy and monthly 09:00 India reminder verified';
END $$;
COMMIT;
