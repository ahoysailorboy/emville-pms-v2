-- Record the authorised approver in INSERT webhook payloads while retaining
-- the pending-to-approved transition required by existing balance triggers.
BEGIN;

CREATE OR REPLACE FUNCTION public.approve_bank_proposal(p_proposal uuid,p_note text,p_payee text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE p public.bank_reconciliation_proposals; b public.bank_statement_lines; s public.bank_reconciliations; base public.main_ledger;
 new_id uuid; actor_name text;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Only admins and owners may approve'; END IF;
 -- Consistent lock order across comparison, resolution and approval.
 SELECT r.* INTO STRICT s FROM public.bank_reconciliations r JOIN public.bank_statement_lines b ON b.reconciliation_id=r.id
  JOIN public.bank_reconciliation_proposals p ON p.line_id=b.id WHERE p.id=p_proposal FOR UPDATE OF r;
 SELECT * INTO STRICT p FROM public.bank_reconciliation_proposals WHERE id=p_proposal FOR UPDATE;
 SELECT * INTO STRICT b FROM public.bank_statement_lines WHERE id=p.line_id FOR UPDATE;
 IF p.status='approved' THEN RETURN p.ledger_id; END IF;
 IF s.status<>'review' OR p.status<>'pending' OR length(trim(coalesce(p_note,'')))=0 OR length(trim(coalesce(p_payee,'')))=0 THEN RAISE EXCEPTION 'Review the proposal, payee and approval note first'; END IF;
 IF b.state IN ('matched','timing','transfer','duplicate') THEN RAISE EXCEPTION 'This bank transaction is already resolved'; END IF;
 -- Serialise ledger changes during final duplicate checks and posting.
 LOCK TABLE public.main_ledger IN SHARE ROW EXCLUSIVE MODE;
 IF NOT p.duplicate_reviewed AND EXISTS(SELECT 1 FROM public.main_ledger l WHERE l.amount=b.amount AND l.transaction_type::text=b.transaction_type AND abs(l.date-b.date)<=3 AND (p.base_ledger_id IS NULL OR l.id<>p.base_ledger_id)) THEN
  RAISE EXCEPTION 'A possible matching entry now exists. Compare or review it before posting'; END IF;
 IF p.kind='adjustment' THEN
  SELECT * INTO STRICT base FROM public.main_ledger WHERE id=p.base_ledger_id FOR UPDATE;
  IF to_jsonb(base)<>p.base_snapshot OR EXISTS(SELECT 1 FROM public.bank_reconciliation_links WHERE ledger_id=base.id) THEN RAISE EXCEPTION 'Original ledger entry changed or was reconciled. Compare again'; END IF;
 ELSE
  IF NOT p.duplicate_reviewed AND EXISTS(SELECT 1 FROM public.main_ledger l WHERE l.amount=b.amount AND l.transaction_type::text=b.transaction_type AND abs(l.date-b.date)<=3) THEN
   RAISE EXCEPTION 'A possible matching ledger entry now exists. Compare or link it before posting'; END IF;
 END IF;
 SELECT coalesce(nullif(full_name,''),email) INTO actor_name FROM public.users WHERE uid=auth.uid();
 -- Existing main-ledger triggers count approvals on pending -> approved, not approved inserts.
 INSERT INTO public.main_ledger(date,amount,transaction_type,transaction_status,created_by,creator_uuid,approved_by,payee_payer_name,remarks,payment_mode)
 VALUES(b.date,p.amount,p.transaction_type::public.main_trx_type,'pending',actor_name,auth.uid(),actor_name,trim(p_payee),
 'Bank reconciliation '||to_char(s.month,'YYYY-MM')||': '||b.description||CASE WHEN b.reference<>'' THEN E'\nReference: '||b.reference ELSE '' END||E'\nApproval: '||trim(p_note),'bank_transfer') RETURNING id INTO new_id;
 UPDATE public.main_ledger SET transaction_status='approved',approved_by=actor_name WHERE id=new_id;
 IF p.kind='adjustment' THEN INSERT INTO public.bank_reconciliation_links(line_id,ledger_id,ledger_snapshot,created_by) VALUES(b.id,base.id,to_jsonb(base),auth.uid()); END IF;
 INSERT INTO public.bank_reconciliation_links(line_id,ledger_id,ledger_snapshot,created_by)
 SELECT b.id,l.id,to_jsonb(l),auth.uid() FROM public.main_ledger l WHERE l.id=new_id;
 UPDATE public.bank_reconciliation_proposals SET status='approved',ledger_id=new_id,approved_by=auth.uid(),approved_at=now(),approval_note=trim(p_note) WHERE id=p.id;
 UPDATE public.bank_statement_lines SET state='matched',resolved_by=auth.uid(),resolution_note=trim(p_note) WHERE id=b.id;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,line_id,actor,action,note) VALUES(s.id,b.id,auth.uid(),'approve_and_post',trim(p_note));
 RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.approve_bank_ledger_reversal(p_proposal uuid,p_note text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE p public.bank_ledger_reversal_proposals; s public.bank_reconciliations; l public.main_ledger; new_id uuid; actor_name text;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Only admins and owners may approve'; END IF;
 SELECT r.* INTO STRICT s FROM public.bank_reconciliations r JOIN public.bank_ledger_reversal_proposals p ON p.reconciliation_id=r.id WHERE p.id=p_proposal FOR UPDATE OF r;
 SELECT * INTO STRICT p FROM public.bank_ledger_reversal_proposals WHERE id=p_proposal FOR UPDATE;
 IF p.status='approved' THEN RETURN p.ledger_id; END IF;
 IF s.status<>'review' OR p.status<>'pending' OR length(trim(coalesce(p_note,'')))=0 THEN RAISE EXCEPTION 'Review the reversal and enter an approval note'; END IF;
 LOCK TABLE public.main_ledger IN SHARE ROW EXCLUSIVE MODE;
 SELECT * INTO STRICT l FROM public.main_ledger WHERE id=p.base_ledger_id FOR UPDATE;
 IF to_jsonb(l)<>p.base_snapshot OR EXISTS(SELECT 1 FROM public.bank_reconciliation_links WHERE ledger_id=l.id) THEN RAISE EXCEPTION 'Original entry changed or was reconciled. Review again'; END IF;
 SELECT coalesce(nullif(full_name,''),email) INTO actor_name FROM public.users WHERE uid=auth.uid();
 INSERT INTO public.main_ledger(date,amount,transaction_type,transaction_status,created_by,creator_uuid,approved_by,payee_payer_name,remarks,payment_mode)
 VALUES(l.date,p.amount,p.transaction_type::public.main_trx_type,'pending',actor_name,auth.uid(),actor_name,l.payee_payer_name,
  'Bank reconciliation reversal of duplicate ledger entry '||l.id::text||E'\nApproval: '||trim(p_note),'bank_transfer') RETURNING id INTO new_id;
 UPDATE public.main_ledger SET transaction_status='approved',approved_by=actor_name WHERE id=new_id;
 INSERT INTO public.bank_ledger_reviews(reconciliation_id,ledger_id,ledger_snapshot,classification,note,actor)
 SELECT s.id,m.id,to_jsonb(m),'duplicate','Approved duplicate reversal: '||trim(p_note),auth.uid() FROM public.main_ledger m WHERE m.id=new_id;
 UPDATE public.bank_ledger_reversal_proposals SET status='approved',ledger_id=new_id,approved_by=auth.uid(),approved_at=now(),approval_note=trim(p_note) WHERE id=p.id;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(s.id,auth.uid(),'approve_duplicate_reversal',trim(p_note));
 RETURN new_id;
END $$;

COMMIT;
