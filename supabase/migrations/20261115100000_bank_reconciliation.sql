BEGIN;
CREATE OR REPLACE FUNCTION public.is_bank_reconciliation_admin()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
 SELECT public.is_authorized_uid(auth.uid()) AND EXISTS
 (SELECT 1 FROM public.users WHERE uid=auth.uid() AND role::text IN ('owner','admin'))
$$;
CREATE TABLE public.bank_reconciliations (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 month date NOT NULL CHECK(month=date_trunc('month',month)::date),
 bank_name text NOT NULL DEFAULT 'Federal Bank',
 file_path text NOT NULL, file_sha256 text NOT NULL,
 opening_balance numeric(14,2) NOT NULL, closing_balance numeric(14,2) NOT NULL,
 uploaded_by uuid NOT NULL REFERENCES public.users(uid),
 status text NOT NULL DEFAULT 'review' CHECK(status IN ('review','completed','archived')),
 created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz,
 completed_by uuid REFERENCES public.users(uid)
);
CREATE UNIQUE INDEX bank_reconciliation_active_month ON public.bank_reconciliations(month) WHERE status<>'archived';
CREATE UNIQUE INDEX bank_reconciliation_active_pdf ON public.bank_reconciliations(file_sha256) WHERE status<>'archived';
CREATE TABLE public.bank_statement_lines (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 reconciliation_id uuid NOT NULL REFERENCES public.bank_reconciliations(id) ON DELETE CASCADE,
 line_number integer NOT NULL, date date NOT NULL, amount numeric(14,2) NOT NULL CHECK(amount>0),
 transaction_type text NOT NULL CHECK(transaction_type IN ('income','expense')),
 description text NOT NULL, reference text NOT NULL DEFAULT '',
 state text NOT NULL DEFAULT 'unmatched' CHECK(state IN ('unmatched','matched','review','pending_approval','timing','transfer','duplicate')),
 resolution_note text, resolved_by uuid REFERENCES public.users(uid),
 UNIQUE(reconciliation_id,line_number)
);
CREATE TABLE public.bank_reconciliation_links (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 line_id uuid NOT NULL REFERENCES public.bank_statement_lines(id) ON DELETE CASCADE,
 ledger_id uuid NOT NULL UNIQUE REFERENCES public.main_ledger(id) ON DELETE RESTRICT,
 ledger_snapshot jsonb NOT NULL, created_by uuid NOT NULL REFERENCES public.users(uid),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.bank_reconciliation_proposals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 line_id uuid NOT NULL UNIQUE REFERENCES public.bank_statement_lines(id) ON DELETE CASCADE,
 kind text NOT NULL CHECK(kind IN ('missing','adjustment')),
 base_ledger_id uuid REFERENCES public.main_ledger(id) ON DELETE RESTRICT,
 base_snapshot jsonb,
 amount numeric(14,2) NOT NULL CHECK(amount>0), transaction_type text NOT NULL CHECK(transaction_type IN ('income','expense')),
 duplicate_reviewed boolean NOT NULL DEFAULT false,
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','dismissed')),
 ledger_id uuid REFERENCES public.main_ledger(id) ON DELETE RESTRICT,
 approved_by uuid REFERENCES public.users(uid), approved_at timestamptz, approval_note text
);
CREATE TABLE public.bank_reconciliation_notes (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), reconciliation_id uuid NOT NULL REFERENCES public.bank_reconciliations(id),
 line_id uuid REFERENCES public.bank_statement_lines(id), actor uuid NOT NULL REFERENCES public.users(uid),
 action text NOT NULL, note text NOT NULL, created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE public.bank_ledger_reviews (
 reconciliation_id uuid NOT NULL REFERENCES public.bank_reconciliations(id),
 ledger_id uuid NOT NULL REFERENCES public.main_ledger(id) ON DELETE RESTRICT,
 ledger_snapshot jsonb NOT NULL, classification text NOT NULL CHECK(classification IN ('timing','duplicate','non_bank')),
 note text NOT NULL, actor uuid NOT NULL REFERENCES public.users(uid), created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(reconciliation_id,ledger_id)
);
CREATE TABLE public.bank_ledger_reversal_proposals (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), reconciliation_id uuid NOT NULL REFERENCES public.bank_reconciliations(id),
 base_ledger_id uuid NOT NULL REFERENCES public.main_ledger(id) ON DELETE RESTRICT,base_snapshot jsonb NOT NULL,
 amount numeric(14,2) NOT NULL CHECK(amount>0),transaction_type text NOT NULL CHECK(transaction_type IN ('income','expense')),
 status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','approved','dismissed')),
 ledger_id uuid REFERENCES public.main_ledger(id),approved_by uuid REFERENCES public.users(uid),approved_at timestamptz,approval_note text,
 UNIQUE(reconciliation_id,base_ledger_id)
);
CREATE TABLE public.bank_reconciliation_reminders (
 month date NOT NULL, recipient uuid NOT NULL REFERENCES public.users(uid),
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(month,recipient)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['bank_reconciliations','bank_statement_lines','bank_reconciliation_links','bank_reconciliation_proposals','bank_reconciliation_notes','bank_ledger_reviews','bank_ledger_reversal_proposals'] LOOP
 EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
 EXECUTE format('CREATE POLICY bank_admin_read ON public.%I FOR SELECT TO authenticated USING(public.is_bank_reconciliation_admin())',t);
 EXECUTE format('GRANT SELECT ON public.%I TO authenticated',t);
 EXECUTE format('GRANT ALL ON public.%I TO service_role',t);
 END LOOP;
END $$;
ALTER TABLE public.bank_reconciliation_reminders ENABLE ROW LEVEL SECURITY;
GRANT ALL ON public.bank_reconciliation_reminders TO service_role;

CREATE OR REPLACE FUNCTION public.create_bank_reconciliation(p_id uuid,p_month date,p_file_path text,p_file_sha256 text,p_opening numeric,p_closing numeric,p_lines jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE item jsonb; n integer:=0; total numeric:=0; d date; a numeric;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Only admins and owners can reconcile bank statements'; END IF;
 IF p_month<>date_trunc('month',p_month)::date OR p_month>=date_trunc('month',current_date)::date THEN RAISE EXCEPTION 'Choose a completed calendar month'; END IF;
 IF p_file_path<>auth.uid()::text||'/'||p_id::text||'.pdf' OR length(p_file_sha256)<>64 THEN RAISE EXCEPTION 'Invalid statement attachment'; END IF;
 IF NOT EXISTS(SELECT 1 FROM storage.objects WHERE bucket_id='bank-statements' AND name=p_file_path) THEN RAISE EXCEPTION 'Upload the original PDF first'; END IF;
 IF jsonb_typeof(p_lines)<>'array' OR jsonb_array_length(p_lines) NOT BETWEEN 0 AND 3000 THEN RAISE EXCEPTION 'Review up to 3000 statement transactions'; END IF;
 FOR item IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  d:=(item->>'date')::date; a:=(item->>'amount')::numeric;
  IF d IS NULL OR d<p_month OR d>=(p_month+interval '1 month')::date OR a IS NULL OR a<=0 OR a<>round(a,2)
   OR coalesce(item->>'transaction_type','') NOT IN ('income','expense') OR length(trim(coalesce(item->>'description','')))=0 THEN RAISE EXCEPTION 'Invalid statement transaction'; END IF;
  total:=total+CASE WHEN item->>'transaction_type'='income' THEN a ELSE -a END;
 END LOOP;
 IF p_opening IS NULL OR p_closing IS NULL OR p_opening<>round(p_opening,2) OR p_closing<>round(p_closing,2) OR p_opening+total<>p_closing THEN
  RAISE EXCEPTION 'Opening balance plus statement transactions must equal the closing balance. Review extraction first'; END IF;
 INSERT INTO public.bank_reconciliations(id,month,file_path,file_sha256,opening_balance,closing_balance,uploaded_by)
 VALUES(p_id,p_month,p_file_path,p_file_sha256,p_opening,p_closing,auth.uid());
 FOR item IN SELECT value FROM jsonb_array_elements(p_lines) LOOP
  n:=n+1;
  INSERT INTO public.bank_statement_lines(reconciliation_id,line_number,date,amount,transaction_type,description,reference)
  VALUES(p_id,n,(item->>'date')::date,(item->>'amount')::numeric,item->>'transaction_type',trim(item->>'description'),coalesce(item->>'reference',''));
 END LOOP;
 UPDATE public.work_reminders SET status='completed',revision=revision+1,updated_at=now() WHERE title='Upload Federal Bank statement · '||to_char(p_month,'Mon YYYY') AND status<>'completed';
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(p_id,auth.uid(),'import','Admin reviewed PDF transactions and statement balances');
 RETURN p_id;
END $$;

CREATE OR REPLACE FUNCTION public.discard_bank_reconciliation(p_id uuid,p_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE s public.bank_reconciliations;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO STRICT s FROM public.bank_reconciliations WHERE id=p_id FOR UPDATE;
 IF s.status<>'review' OR length(trim(coalesce(p_note,'')))=0 THEN RAISE EXCEPTION 'Reopen the draft and explain why it is being replaced'; END IF;
 IF EXISTS(SELECT 1 FROM public.bank_reconciliation_proposals p JOIN public.bank_statement_lines b ON b.id=p.line_id WHERE b.reconciliation_id=p_id AND p.status='approved')
 OR EXISTS(SELECT 1 FROM public.bank_ledger_reversal_proposals WHERE reconciliation_id=p_id AND status='approved') THEN RAISE EXCEPTION 'This statement has posted entries and cannot be discarded'; END IF;
 DELETE FROM public.bank_reconciliation_links WHERE line_id IN (SELECT id FROM public.bank_statement_lines WHERE reconciliation_id=p_id);
 DELETE FROM public.bank_ledger_reviews WHERE reconciliation_id=p_id;
 UPDATE public.bank_reconciliations SET status='archived' WHERE id=p_id;
 UPDATE public.work_reminders SET status='open',revision=revision+1,updated_at=now() WHERE title='Upload Federal Bank statement · '||to_char(s.month,'Mon YYYY');
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(p_id,auth.uid(),'discard_draft',trim(p_note));
END $$;

CREATE OR REPLACE FUNCTION public.compare_bank_reconciliation(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE s public.bank_reconciliations; b public.bank_statement_lines; candidate public.main_ledger;
 count_candidates integer; shared integer; signed_bank numeric; signed_base numeric; diff numeric;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO STRICT s FROM public.bank_reconciliations WHERE id=p_id FOR UPDATE;
 IF s.status<>'review' THEN RAISE EXCEPTION 'Reopen this reconciliation before comparing'; END IF;
 -- Lock ledger rows while taking matching snapshots; no ledger data is changed.
 PERFORM 1 FROM public.main_ledger WHERE date>=s.month-3 AND date<(s.month+interval '1 month')::date+3 FOR SHARE;
 DELETE FROM public.bank_reconciliation_proposals WHERE line_id IN (SELECT id FROM public.bank_statement_lines WHERE reconciliation_id=p_id) AND status<>'approved';
 FOR b IN SELECT * FROM public.bank_statement_lines WHERE reconciliation_id=p_id AND state NOT IN ('matched','timing','transfer','duplicate') ORDER BY line_number FOR UPDATE LOOP
  SELECT count(*) INTO count_candidates FROM public.main_ledger l
   WHERE l.amount=b.amount AND l.transaction_type::text=b.transaction_type AND abs(l.date-b.date)<=3
   AND NOT EXISTS(SELECT 1 FROM public.bank_reconciliation_links k WHERE k.ledger_id=l.id) AND NOT EXISTS(SELECT 1 FROM public.bank_ledger_reviews v WHERE v.ledger_id=l.id AND v.classification IN ('duplicate','non_bank') AND v.ledger_snapshot=to_jsonb(l));
  IF count_candidates=1 THEN
   SELECT * INTO candidate FROM public.main_ledger l WHERE l.amount=b.amount AND l.transaction_type::text=b.transaction_type AND abs(l.date-b.date)<=3
     AND NOT EXISTS(SELECT 1 FROM public.bank_reconciliation_links k WHERE k.ledger_id=l.id) AND NOT EXISTS(SELECT 1 FROM public.bank_ledger_reviews v WHERE v.ledger_id=l.id AND v.classification IN ('duplicate','non_bank') AND v.ledger_snapshot=to_jsonb(l));
   SELECT count(*) INTO shared FROM public.bank_statement_lines other WHERE other.reconciliation_id=p_id
    AND other.state NOT IN ('timing','transfer','duplicate') AND other.amount=candidate.amount
    AND other.transaction_type=candidate.transaction_type::text AND abs(other.date-candidate.date)<=3;
   IF shared=1 AND candidate.transaction_status::text='approved' THEN
    INSERT INTO public.bank_reconciliation_links(line_id,ledger_id,ledger_snapshot,created_by) VALUES(b.id,candidate.id,to_jsonb(candidate),auth.uid());
    UPDATE public.bank_statement_lines SET state='matched' WHERE id=b.id;
    CONTINUE;
   ELSIF shared=1 THEN UPDATE public.bank_statement_lines SET state='pending_approval' WHERE id=b.id; CONTINUE;
   END IF;
  END IF;
  IF count_candidates>0 THEN UPDATE public.bank_statement_lines SET state='review' WHERE id=b.id; CONTINUE; END IF;
  -- Reference match with a different amount: propose only the adjustment, never the full amount again.
  SELECT count(*) INTO count_candidates FROM public.main_ledger l
   WHERE length(regexp_replace(b.reference,'[^a-zA-Z0-9]','','g'))>=6
   AND position(upper(regexp_replace(b.reference,'[^a-zA-Z0-9]','','g')) in upper(regexp_replace(coalesce(l.remarks,''),'[^a-zA-Z0-9]','','g')))>0
   AND abs(l.date-b.date)<=3
   AND NOT EXISTS(SELECT 1 FROM public.bank_reconciliation_links k WHERE k.ledger_id=l.id) AND NOT EXISTS(SELECT 1 FROM public.bank_ledger_reviews v WHERE v.ledger_id=l.id AND v.classification IN ('duplicate','non_bank') AND v.ledger_snapshot=to_jsonb(l));
  IF count_candidates=1 THEN
   SELECT * INTO candidate FROM public.main_ledger l WHERE
    position(upper(regexp_replace(b.reference,'[^a-zA-Z0-9]','','g')) in upper(regexp_replace(coalesce(l.remarks,''),'[^a-zA-Z0-9]','','g')))>0
    AND abs(l.date-b.date)<=3
    AND NOT EXISTS(SELECT 1 FROM public.bank_reconciliation_links k WHERE k.ledger_id=l.id) AND NOT EXISTS(SELECT 1 FROM public.bank_ledger_reviews v WHERE v.ledger_id=l.id AND v.classification IN ('duplicate','non_bank') AND v.ledger_snapshot=to_jsonb(l)) LIMIT 1;
   IF candidate.transaction_status::text<>'approved' THEN UPDATE public.bank_statement_lines SET state='pending_approval' WHERE id=b.id; CONTINUE; END IF;
   signed_bank:=CASE WHEN b.transaction_type='income' THEN b.amount ELSE -b.amount END;
   signed_base:=CASE WHEN candidate.transaction_type::text='income' THEN candidate.amount ELSE -candidate.amount END;
   diff:=signed_bank-signed_base;
   IF diff<>0 THEN INSERT INTO public.bank_reconciliation_proposals(line_id,kind,base_ledger_id,base_snapshot,amount,transaction_type)
    VALUES(b.id,'adjustment',candidate.id,to_jsonb(candidate),abs(diff),CASE WHEN diff>0 THEN 'income' ELSE 'expense' END);
   END IF;
   UPDATE public.bank_statement_lines SET state='review' WHERE id=b.id;
  ELSE
   -- Existing equal-value transactions must be reviewed rather than duplicated.
   IF EXISTS(SELECT 1 FROM public.main_ledger l WHERE l.amount=b.amount AND l.transaction_type::text=b.transaction_type AND abs(l.date-b.date)<=3) THEN
    UPDATE public.bank_statement_lines SET state='review' WHERE id=b.id;
   ELSE
    INSERT INTO public.bank_reconciliation_proposals(line_id,kind,amount,transaction_type)
    VALUES(b.id,'missing',b.amount,b.transaction_type) ON CONFLICT(line_id) DO NOTHING;
    UPDATE public.bank_statement_lines SET state='unmatched' WHERE id=b.id;
   END IF;
  END IF;
 END LOOP;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(p_id,auth.uid(),'compare','Compared statement with current bank ledger; proposals remain unposted');
END $$;

CREATE OR REPLACE FUNCTION public.resolve_bank_line(p_line uuid,p_action text,p_note text,p_ledger uuid DEFAULT null)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE b public.bank_statement_lines; l public.main_ledger; s public.bank_reconciliations; diff numeric;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT r.* INTO STRICT s FROM public.bank_reconciliations r JOIN public.bank_statement_lines b ON b.reconciliation_id=r.id WHERE b.id=p_line FOR UPDATE OF r;
 SELECT * INTO STRICT b FROM public.bank_statement_lines WHERE id=p_line FOR UPDATE;
 IF s.status<>'review' OR length(trim(coalesce(p_note,'')))=0 THEN RAISE EXCEPTION 'Reopen the month and enter a review note'; END IF;
 IF EXISTS(SELECT 1 FROM public.bank_reconciliation_proposals WHERE line_id=p_line AND status='approved') THEN RAISE EXCEPTION 'Posted adjustments must be reviewed through the ledger'; END IF;
 IF p_action IN ('link','adjustment') THEN
  SELECT * INTO STRICT l FROM public.main_ledger WHERE id=p_ledger FOR UPDATE;
  IF l.transaction_status::text<>'approved' OR abs(l.date-b.date)>31 OR (p_action='link' AND (l.amount<>b.amount OR l.transaction_type::text<>b.transaction_type)) THEN RAISE EXCEPTION 'Choose an approved ledger entry with the same signed amount within 31 days'; END IF;
  IF p_action='adjustment' THEN
   IF EXISTS(SELECT 1 FROM public.bank_reconciliation_links WHERE ledger_id=l.id) THEN RAISE EXCEPTION 'This ledger entry is already reconciled'; END IF;
   diff:=CASE WHEN b.transaction_type='income' THEN b.amount ELSE -b.amount END-CASE WHEN l.transaction_type::text='income' THEN l.amount ELSE -l.amount END;
   IF diff=0 THEN RAISE EXCEPTION 'Amounts agree; link this entry instead'; END IF;
   INSERT INTO public.bank_reconciliation_proposals(line_id,kind,base_ledger_id,base_snapshot,amount,transaction_type,approval_note)
   VALUES(p_line,'adjustment',l.id,to_jsonb(l),abs(diff),CASE WHEN diff>0 THEN 'income' ELSE 'expense' END,trim(p_note)) ON CONFLICT(line_id)
   DO UPDATE SET kind='adjustment',base_ledger_id=excluded.base_ledger_id,base_snapshot=excluded.base_snapshot,amount=excluded.amount,transaction_type=excluded.transaction_type,status='pending',duplicate_reviewed=false,approval_note=excluded.approval_note;
   UPDATE public.bank_statement_lines SET state='review',resolution_note=p_note,resolved_by=auth.uid() WHERE id=p_line;
  ELSE
  DELETE FROM public.bank_reconciliation_links WHERE line_id=p_line;
  INSERT INTO public.bank_reconciliation_links(line_id,ledger_id,ledger_snapshot,created_by) VALUES(p_line,l.id,to_jsonb(l),auth.uid());
  UPDATE public.bank_statement_lines SET state='matched',resolution_note=p_note,resolved_by=auth.uid() WHERE id=p_line;
  END IF;
 ELSIF p_action IN ('timing','transfer','duplicate','unmatched') THEN
  DELETE FROM public.bank_reconciliation_links WHERE line_id=p_line;
  UPDATE public.bank_statement_lines SET state=p_action,resolution_note=p_note,resolved_by=auth.uid() WHERE id=p_line;
 ELSE RAISE EXCEPTION 'Invalid resolution'; END IF;
 IF p_action<>'adjustment' THEN UPDATE public.bank_reconciliation_proposals SET status='dismissed',approval_note=p_note WHERE line_id=p_line AND status='pending'; END IF;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,line_id,actor,action,note) VALUES(b.reconciliation_id,p_line,auth.uid(),p_action,p_note);
END $$;

CREATE OR REPLACE FUNCTION public.propose_distinct_bank_entry(p_line uuid,p_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE b public.bank_statement_lines; s public.bank_reconciliations;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT r.* INTO STRICT s FROM public.bank_reconciliations r JOIN public.bank_statement_lines b ON b.reconciliation_id=r.id WHERE b.id=p_line FOR UPDATE OF r;
 SELECT * INTO STRICT b FROM public.bank_statement_lines WHERE id=p_line FOR UPDATE;
 IF s.status<>'review' OR b.state IN ('matched','timing','transfer','duplicate') OR length(trim(coalesce(p_note,'')))<10 THEN RAISE EXCEPTION 'Explain why this is a distinct business transaction before proposing an entry'; END IF;
 IF EXISTS(SELECT 1 FROM public.bank_reconciliation_proposals WHERE line_id=p_line AND status='approved') THEN RAISE EXCEPTION 'An entry was already posted'; END IF;
 INSERT INTO public.bank_reconciliation_proposals(line_id,kind,amount,transaction_type,duplicate_reviewed,approval_note)
 VALUES(p_line,'missing',b.amount,b.transaction_type,true,trim(p_note)) ON CONFLICT(line_id)
 DO UPDATE SET kind='missing',amount=excluded.amount,transaction_type=excluded.transaction_type,base_ledger_id=null,base_snapshot=null,duplicate_reviewed=true,status='pending',approval_note=excluded.approval_note;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,line_id,actor,action,note) VALUES(s.id,p_line,auth.uid(),'propose_distinct',trim(p_note));
END $$;

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
 INSERT INTO public.main_ledger(date,amount,transaction_type,transaction_status,created_by,creator_uuid,payee_payer_name,remarks,payment_mode)
 VALUES(b.date,p.amount,p.transaction_type::public.main_trx_type,'pending',actor_name,auth.uid(),trim(p_payee),
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

CREATE OR REPLACE FUNCTION public.review_unmatched_bank_ledger(p_id uuid,p_ledger uuid,p_classification text,p_note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE s public.bank_reconciliations; l public.main_ledger;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO STRICT s FROM public.bank_reconciliations WHERE id=p_id FOR UPDATE;
 SELECT * INTO STRICT l FROM public.main_ledger WHERE id=p_ledger FOR SHARE;
 IF s.status<>'review' OR p_classification NOT IN ('timing','duplicate','non_bank') OR length(trim(coalesce(p_note,'')))=0
 OR l.date<s.month OR l.date>=(s.month+interval '1 month')::date OR EXISTS(SELECT 1 FROM public.bank_reconciliation_links WHERE ledger_id=p_ledger) THEN RAISE EXCEPTION 'Choose an unmatched ledger entry and add a review note'; END IF;
 IF EXISTS(SELECT 1 FROM public.bank_ledger_reversal_proposals WHERE reconciliation_id=p_id AND base_ledger_id=p_ledger AND status='approved') THEN RAISE EXCEPTION 'This duplicate was already reversed'; END IF;
 IF p_classification='duplicate' THEN
  IF l.transaction_status::text<>'approved' THEN RAISE EXCEPTION 'Delete an unapproved duplicate through ledger approvals; do not reverse it as approved income or expense'; END IF;
  INSERT INTO public.bank_ledger_reversal_proposals(reconciliation_id,base_ledger_id,base_snapshot,amount,transaction_type)
  VALUES(p_id,l.id,to_jsonb(l),l.amount,CASE WHEN l.transaction_type::text='income' THEN 'expense' ELSE 'income' END)
  ON CONFLICT(reconciliation_id,base_ledger_id) DO UPDATE SET base_snapshot=excluded.base_snapshot,amount=excluded.amount,transaction_type=excluded.transaction_type,status='pending';
 ELSE
  UPDATE public.bank_ledger_reversal_proposals SET status='dismissed' WHERE reconciliation_id=p_id AND base_ledger_id=p_ledger AND status='pending';
 END IF;
 INSERT INTO public.bank_ledger_reviews(reconciliation_id,ledger_id,ledger_snapshot,classification,note,actor)
 VALUES(p_id,p_ledger,to_jsonb(l),p_classification,trim(p_note),auth.uid()) ON CONFLICT(reconciliation_id,ledger_id)
 DO UPDATE SET ledger_snapshot=excluded.ledger_snapshot,classification=excluded.classification,note=excluded.note,actor=excluded.actor,created_at=now();
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(p_id,auth.uid(),'ledger_'||p_classification,trim(p_note));
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
 INSERT INTO public.main_ledger(date,amount,transaction_type,transaction_status,created_by,creator_uuid,payee_payer_name,remarks,payment_mode)
 VALUES(l.date,p.amount,p.transaction_type::public.main_trx_type,'pending',actor_name,auth.uid(),l.payee_payer_name,
  'Bank reconciliation reversal of duplicate ledger entry '||l.id::text||E'\nApproval: '||trim(p_note),'bank_transfer') RETURNING id INTO new_id;
 UPDATE public.main_ledger SET transaction_status='approved',approved_by=actor_name WHERE id=new_id;
 INSERT INTO public.bank_ledger_reviews(reconciliation_id,ledger_id,ledger_snapshot,classification,note,actor)
 SELECT s.id,m.id,to_jsonb(m),'duplicate','Approved duplicate reversal: '||trim(p_note),auth.uid() FROM public.main_ledger m WHERE m.id=new_id;
 UPDATE public.bank_ledger_reversal_proposals SET status='approved',ledger_id=new_id,approved_by=auth.uid(),approved_at=now(),approval_note=trim(p_note) WHERE id=p.id;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(s.id,auth.uid(),'approve_duplicate_reversal',trim(p_note));
 RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.set_bank_reconciliation_status(p_id uuid,p_complete boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE s public.bank_reconciliations;
BEGIN
 IF NOT public.is_bank_reconciliation_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
 SELECT * INTO STRICT s FROM public.bank_reconciliations WHERE id=p_id FOR UPDATE;
 IF s.status='archived' THEN RAISE EXCEPTION 'This draft has been replaced'; END IF;
 IF p_complete THEN
  IF EXISTS(SELECT 1 FROM public.bank_ledger_reversal_proposals WHERE reconciliation_id=p_id AND status='pending') THEN RAISE EXCEPTION 'Approve or dismiss proposed duplicate reversals first'; END IF;
  IF EXISTS(SELECT 1 FROM public.bank_statement_lines WHERE reconciliation_id=p_id AND state NOT IN ('matched','timing','transfer','duplicate')) THEN RAISE EXCEPTION 'Resolve every statement transaction first'; END IF;
  IF EXISTS(SELECT 1 FROM public.main_ledger l WHERE l.date>=s.month AND l.date<(s.month+interval '1 month')::date
   AND NOT EXISTS(SELECT 1 FROM public.bank_reconciliation_links k WHERE k.ledger_id=l.id) AND NOT EXISTS(SELECT 1 FROM public.bank_ledger_reviews v WHERE v.ledger_id=l.id AND v.classification IN ('duplicate','non_bank') AND v.ledger_snapshot=to_jsonb(l))
   AND NOT EXISTS(SELECT 1 FROM public.bank_ledger_reviews v WHERE v.reconciliation_id=p_id AND v.ledger_id=l.id AND v.ledger_snapshot=to_jsonb(l)))
   THEN RAISE EXCEPTION 'Review bank-ledger entries missing from the statement as well'; END IF;
  IF EXISTS(SELECT 1 FROM public.bank_statement_lines b WHERE b.reconciliation_id=p_id AND b.state='matched' AND
   coalesce((SELECT sum(CASE WHEN l.transaction_type::text='income' THEN l.amount ELSE -l.amount END)
    FROM public.bank_reconciliation_links k JOIN public.main_ledger l ON l.id=k.ledger_id WHERE k.line_id=b.id),0)
    <>CASE WHEN b.transaction_type='income' THEN b.amount ELSE -b.amount END) THEN RAISE EXCEPTION 'Linked ledger amounts do not agree with the bank statement'; END IF;
  IF EXISTS(SELECT 1 FROM public.bank_reconciliation_links k JOIN public.bank_statement_lines b ON b.id=k.line_id JOIN public.main_ledger l ON l.id=k.ledger_id
    WHERE b.reconciliation_id=p_id AND to_jsonb(l)<>k.ledger_snapshot) THEN RAISE EXCEPTION 'A linked ledger entry changed. Review it before completing'; END IF;
 END IF;
 UPDATE public.bank_reconciliations SET status=CASE WHEN p_complete THEN 'completed' ELSE 'review' END,
 completed_by=CASE WHEN p_complete THEN auth.uid() ELSE null END,completed_at=CASE WHEN p_complete THEN now() ELSE null END WHERE id=p_id;
 INSERT INTO public.bank_reconciliation_notes(reconciliation_id,actor,action,note) VALUES(p_id,auth.uid(),CASE WHEN p_complete THEN 'complete' ELSE 'reopen' END,'Admin reviewed bank reconciliation');
END $$;

ALTER TABLE public.task_notification_queue ADD COLUMN IF NOT EXISTS route text;

CREATE OR REPLACE FUNCTION public.queue_monthly_bank_reconciliation_reminders()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
#variable_conflict use_column
DECLARE m date:=(date_trunc('month',now() AT TIME ZONE 'Asia/Kolkata')-interval '1 month')::date; u record;
BEGIN
 IF extract(day FROM now() AT TIME ZONE 'Asia/Kolkata')<2 THEN RETURN; END IF;
 IF EXISTS(SELECT 1 FROM public.bank_reconciliations WHERE month=m AND status<>'archived') THEN RETURN; END IF;
 FOR u IN SELECT uid FROM public.users WHERE is_authorized AND role::text IN ('owner','admin') LOOP
  INSERT INTO public.bank_reconciliation_reminders(month,recipient) VALUES(m,u.uid) ON CONFLICT DO NOTHING;
  IF FOUND THEN
   INSERT INTO public.work_reminders(title,description,created_by,assigned_to,due_at)
   VALUES('Upload Federal Bank statement · '||to_char(m,'Mon YYYY'),'Download the monthly bank account statement PDF and upload it in Accounts → Bank reconciliation.',u.uid,u.uid,now());
   INSERT INTO public.task_notification_queue(recipient,title,message,route) VALUES(u.uid,'Monthly bank reconciliation',
    'Download and upload the Federal Bank statement for '||to_char(m,'Mon YYYY')||'. Open Accounts → Bank reconciliation.','bank_reconciliation');
  END IF;
 END LOOP;
END $$;
-- Access only through validated RPCs; clients cannot directly approve or forge imports.
DO $$ DECLARE f record; BEGIN
 FOR f IN SELECT oid::regprocedure AS sig FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname IN
 ('create_bank_reconciliation','discard_bank_reconciliation','compare_bank_reconciliation','propose_distinct_bank_entry','resolve_bank_line','approve_bank_proposal','set_bank_reconciliation_status','review_unmatched_bank_ledger','approve_bank_ledger_reversal') LOOP
 EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC',f.sig);
 EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated',f.sig);
 END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.queue_monthly_bank_reconciliation_reminders() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.queue_monthly_bank_reconciliation_reminders() TO service_role;

INSERT INTO storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
VALUES('bank-statements','bank-statements',false,10485760,ARRAY['application/pdf']) ON CONFLICT(id) DO UPDATE SET public=false,file_size_limit=10485760,allowed_mime_types=ARRAY['application/pdf'];
CREATE POLICY bank_statement_upload ON storage.objects FOR INSERT TO authenticated
 WITH CHECK(bucket_id='bank-statements' AND public.is_bank_reconciliation_admin() AND (storage.foldername(name))[1]=auth.uid()::text);
CREATE POLICY bank_statement_read ON storage.objects FOR SELECT TO authenticated
 USING(bucket_id='bank-statements' AND public.is_bank_reconciliation_admin());
CREATE POLICY bank_statement_remove ON storage.objects FOR DELETE TO authenticated
 USING(bucket_id='bank-statements' AND public.is_bank_reconciliation_admin() AND (storage.foldername(name))[1]=auth.uid()::text
 AND NOT EXISTS(SELECT 1 FROM public.bank_reconciliations WHERE file_path=name));
-- 09:00 India time on the 2nd of every month (cron uses UTC).
SELECT cron.schedule('emville-monthly-bank-reconciliation','30 3 2 * *','select public.queue_monthly_bank_reconciliation_reminders();');
COMMIT;
