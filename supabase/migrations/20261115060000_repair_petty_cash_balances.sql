BEGIN;
-- Serialize writes while replacing trigger functions and reconciling.
LOCK TABLE public.petty_cash_ledger IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.petty_cash_balance IN SHARE ROW EXCLUSIVE MODE;

-- Maintain both balances with atomic signed deltas on every ledger mutation.
-- Approved rows may be inserted directly; edits may change amount/type/status.
CREATE OR REPLACE FUNCTION public.petty_cash_after_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 signed_amount numeric := CASE WHEN NEW.transaction_type='income' THEN NEW.amount
                               WHEN NEW.transaction_type='expense' THEN -NEW.amount ELSE 0 END;
BEGIN
 UPDATE public.petty_cash_balance
 SET ledger_balance=ledger_balance+signed_amount,
     approved_balance=approved_balance+CASE WHEN NEW.transaction_status='approved' THEN signed_amount ELSE 0 END
 WHERE id=1;
 RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.petty_cash_after_update()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 old_signed numeric := CASE WHEN OLD.transaction_type='income' THEN OLD.amount
                            WHEN OLD.transaction_type='expense' THEN -OLD.amount ELSE 0 END;
 new_signed numeric := CASE WHEN NEW.transaction_type='income' THEN NEW.amount
                            WHEN NEW.transaction_type='expense' THEN -NEW.amount ELSE 0 END;
BEGIN
 UPDATE public.petty_cash_balance
 SET ledger_balance=ledger_balance+new_signed-old_signed,
     approved_balance=approved_balance
       +CASE WHEN NEW.transaction_status='approved' THEN new_signed ELSE 0 END
       -CASE WHEN OLD.transaction_status='approved' THEN old_signed ELSE 0 END
 WHERE id=1;
 RETURN NEW;
END $$;

-- Use the same atomic approach on deletion, avoiding concurrent full-sum snapshots.
CREATE OR REPLACE FUNCTION public.petty_cash_after_delete()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
 signed_amount numeric := CASE WHEN OLD.transaction_type='income' THEN OLD.amount
                               WHEN OLD.transaction_type='expense' THEN -OLD.amount ELSE 0 END;
BEGIN
 UPDATE public.petty_cash_balance
 SET ledger_balance=ledger_balance-signed_amount,
     approved_balance=approved_balance-CASE WHEN OLD.transaction_status='approved' THEN signed_amount ELSE 0 END
 WHERE id=1;
 RETURN OLD;
END $$;

-- Reconcile once; existing triggers remain attached.
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.petty_cash_balance WHERE id=1) THEN
  RAISE EXCEPTION 'Petty cash balance row id=1 is missing';
 END IF;
END $$;
SELECT public.petty_cash_recalc_balances();

COMMIT;
