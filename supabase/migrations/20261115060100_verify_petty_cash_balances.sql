-- Read-only invariant check after the repair. Does not modify financial records.
DO $$
DECLARE
 stored_ledger numeric;
 stored_approved numeric;
 computed_ledger numeric;
 computed_approved numeric;
 ledger_rows bigint;
BEGIN
 WITH totals AS (
  SELECT count(*) AS n,
   coalesce(sum(CASE WHEN transaction_type='income' THEN amount WHEN transaction_type='expense' THEN -amount ELSE 0 END),0) AS all_net,
   coalesce(sum(CASE WHEN transaction_status='approved' THEN CASE WHEN transaction_type='income' THEN amount WHEN transaction_type='expense' THEN -amount ELSE 0 END ELSE 0 END),0) AS approved_net
  FROM public.petty_cash_ledger
 )
 SELECT b.ledger_balance,b.approved_balance,t.all_net,t.approved_net,t.n
 INTO stored_ledger,stored_approved,computed_ledger,computed_approved,ledger_rows
 FROM public.petty_cash_balance b CROSS JOIN totals t WHERE b.id=1;
 IF NOT FOUND OR stored_ledger IS DISTINCT FROM computed_ledger OR stored_approved IS DISTINCT FROM computed_approved THEN
  RAISE EXCEPTION 'Petty cash verification failed: stored ledger %, approved %; calculated ledger %, approved %',stored_ledger,stored_approved,computed_ledger,computed_approved;
 END IF;
 RAISE NOTICE 'Petty cash verified: ledger balance %, approved balance %, ledger rows %',stored_ledger,stored_approved,ledger_rows;
END $$;
