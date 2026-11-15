-- Personal/assigned one-off work stays separate from the recurring PMS master.
create table public.work_reminders (
 id uuid primary key default gen_random_uuid(),
 title text not null check (length(trim(title)) between 1 and 200),
 description text not null default '',
 created_by uuid not null references public.users(uid),
 assigned_to uuid not null references public.users(uid),
 due_at timestamptz not null,
 status text not null default 'open' check (status in ('open','postponed','completed')),
 revision integer not null default 0,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index on public.work_reminders(assigned_to, due_at);
create table public.work_reminder_activity (
 id uuid primary key default gen_random_uuid(),
 reminder_id uuid not null references public.work_reminders(id) on delete cascade,
 actor uuid not null references public.users(uid),
 action text not null check (action in ('created','remark','completed','postponed')),
 remarks text not null default '',
 due_at timestamptz,
 created_at timestamptz not null default now()
);
create table public.task_notification_queue (
 id uuid primary key default gen_random_uuid(),
 recipient uuid not null references public.users(uid),
 title text not null,
 message text not null,
 reminder_id uuid references public.work_reminders(id),
 job_seq integer,
 delivered_at timestamptz,
 attempts integer not null default 0,
 next_attempt_at timestamptz not null default now(),
 created_at timestamptz not null default now()
);
alter table public.work_reminders enable row level security;
alter table public.work_reminder_activity enable row level security;
alter table public.task_notification_queue enable row level security;
create or replace function public.can_manage_work_reminder(r public.work_reminders)
returns boolean language sql stable security definer set search_path=public as $$
 select public.is_authorized_uid(auth.uid()) and
 (r.created_by=auth.uid() or r.assigned_to=auth.uid() or exists
 (select 1 from public.users where uid=auth.uid() and role::text in ('owner','admin')))
$$;
create policy reminder_read on public.work_reminders for select to authenticated
 using(public.can_manage_work_reminder(work_reminders));
create policy reminder_activity_read on public.work_reminder_activity for select to authenticated
 using(exists(select 1 from public.work_reminders r where r.id=reminder_id and public.can_manage_work_reminder(r)));
-- Writes use RPCs; clients cannot forge actors, revisions or notification targets.
create or replace function public.reminder_people()
returns table(uid uuid, full_name text) language sql stable security definer set search_path=public as $$
 select u.uid, coalesce(nullif(u.full_name,''),u.email) from public.users u
 where u.is_authorized and public.is_authorized_uid(auth.uid()) order by 2
$$;
create or replace function public.create_work_reminder(p_title text,p_description text,p_assigned_to uuid,p_due_at timestamptz)
returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
 if not public.is_authorized_uid(auth.uid()) then raise exception 'Not authorized'; end if;
 if not exists(select 1 from public.users where uid=p_assigned_to and is_authorized) then raise exception 'Assignee is not authorized'; end if;
 if p_due_at <= now() then raise exception 'Choose a future reminder time'; end if;
 insert into public.work_reminders(title,description,created_by,assigned_to,due_at)
 values(trim(p_title),coalesce(p_description,''),auth.uid(),p_assigned_to,p_due_at) returning id into rid;
 insert into public.work_reminder_activity(reminder_id,actor,action,due_at) values(rid,auth.uid(),'created',p_due_at);
 insert into public.task_notification_queue(recipient,title,message,reminder_id)
 values(p_assigned_to,'New task assigned',trim(p_title),rid);
 return rid;
end $$;
create or replace function public.update_work_reminder(p_id uuid,p_revision integer,p_action text,p_remarks text,p_due_at timestamptz default null)
returns void language plpgsql security definer set search_path=public as $$
declare r public.work_reminders; target uuid;
begin
 select * into r from public.work_reminders where id=p_id for update;
 if not found or not public.can_manage_work_reminder(r) then raise exception 'Task unavailable or not authorized'; end if;
 if r.revision<>p_revision then raise exception 'This task changed. Refresh and try again'; end if;
 if r.status='completed' then raise exception 'Task is already completed'; end if;
 if p_action not in ('remark','completed','postponed') or length(trim(coalesce(p_remarks,'')))=0 then raise exception 'Action and remarks are required'; end if;
 if p_action='postponed' and (p_due_at is null or p_due_at<=now()) then raise exception 'Choose a future follow-up time'; end if;
 update public.work_reminders set status=case when p_action='remark' then status else p_action end,
 due_at=case when p_action='postponed' then p_due_at else due_at end,revision=revision+1,updated_at=now() where id=p_id;
 insert into public.work_reminder_activity(reminder_id,actor,action,remarks,due_at)
 values(p_id,auth.uid(),p_action,trim(p_remarks),case when p_action='postponed' then p_due_at else null end);
 -- All owners/admins except actor, plus involved users. No role tags trusted from clients.
 for target in select uid from public.users where is_authorized and uid<>auth.uid()
 and (role::text in ('owner','admin') or uid=r.created_by or uid=r.assigned_to) loop
 insert into public.task_notification_queue(recipient,title,message,reminder_id)
 values(target,'Task '||p_action,r.title||': '||trim(p_remarks),p_id);
 end loop;
end $$;
create table public.pms_task_notes (
 id uuid primary key default gen_random_uuid(), job_seq integer not null,
 actor uuid not null references public.users(uid), remarks text not null,
 action text not null check(action in ('remark','postponed')),
 follow_up date, created_at timestamptz not null default now()
);
alter table public.pms_task_notes enable row level security;
create policy pms_notes_read on public.pms_task_notes for select to authenticated
 using(public.is_authorized_uid(auth.uid()));

-- Existing maintenance actions also notify the other admins and owners.
create or replace function public.queue_pms_activity_notification()
returns trigger language plpgsql security definer set search_path=public as $$
declare target uuid; actor uuid := auth.uid();
begin
 if actor is null then return new; end if;
 if to_regclass('public.pms_task_notes') is not null and exists
 (select 1 from public.pms_task_notes n where n.job_seq=new.job_seq and n.actor=auth.uid() and n.created_at=transaction_timestamp())
 then return new; end if;
 if new.remarks is distinct from old.remarks or new.last_done_date is distinct from old.last_done_date
 or new.postponed is distinct from old.postponed then
 for target in select uid from public.users where is_authorized and uid<>actor and role::text in ('owner','admin') loop
 insert into public.task_notification_queue(recipient,title,message,job_seq)
 values(target,'Maintenance task updated',new.task_name||': '||coalesce(new.remarks,''),new.job_seq);
 end loop;
 end if;
 return new;
end $$;
create trigger pms_activity_notify after update on public.main_pms_db for each row execute function public.queue_pms_activity_notification();
revoke all on function public.create_work_reminder(text,text,uuid,timestamptz) from public;
revoke all on function public.update_work_reminder(uuid,integer,text,text,timestamptz) from public;
revoke all on function public.reminder_people() from public;
grant execute on function public.create_work_reminder(text,text,uuid,timestamptz),public.update_work_reminder(uuid,integer,text,text,timestamptz),public.reminder_people() to authenticated;
create or replace function public.add_pms_task_note(p_job_seq integer,p_remarks text,p_follow_up date default null)
returns void language plpgsql security definer set search_path=public as $$
begin
 if not public.is_authorized_uid(auth.uid()) then raise exception 'Not authorized'; end if;
 if length(trim(coalesce(p_remarks,'')))=0 then raise exception 'Remarks required'; end if;
 if p_follow_up is not null and p_follow_up<current_date then raise exception 'Choose a future date'; end if;
 perform 1 from public.main_pms_db where job_seq=p_job_seq for update;
 if not found then raise exception 'Task not found'; end if;
 insert into public.pms_task_notes(job_seq,actor,remarks,action,follow_up)
 values(p_job_seq,auth.uid(),trim(p_remarks),case when p_follow_up is null then 'remark' else 'postponed' end,p_follow_up);
 update public.main_pms_db set remarks=trim(p_remarks),user_uuid=auth.uid(),updated_date=now(),
 next_due_date=coalesce(p_follow_up,next_due_date),
 postponed=case when p_follow_up is not null then 'no' else postponed end where job_seq=p_job_seq;
 -- Queue even when somebody enters the same remarks again.
 insert into public.task_notification_queue(recipient,title,message,job_seq)
 select uid,'Maintenance task updated',trim(p_remarks),p_job_seq from public.users
 where is_authorized and uid<>auth.uid() and role::text in ('owner','admin');
end $$;
revoke all on function public.add_pms_task_note(integer,text,date) from public;
grant execute on function public.add_pms_task_note(integer,text,date) to authenticated;

-- Explicit grants; RLS still controls each visible row. Queue is server-only.
grant select on public.work_reminders,public.work_reminder_activity,public.pms_task_notes to authenticated;
revoke all on public.task_notification_queue from anon,authenticated;
grant all on public.work_reminders,public.work_reminder_activity,public.pms_task_notes,public.task_notification_queue to service_role;
