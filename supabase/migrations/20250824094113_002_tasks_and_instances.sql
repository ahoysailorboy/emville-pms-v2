-- ============ ENUMS ============
create type task_frequency as enum ('daily','weekly','monthly','after_x_days');
create type task_status    as enum ('upcoming','overdue','done','postponed');
create type post_status    as enum ('pending','approved','rejected');

-- ============ TABLES ============
create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  frequency task_frequency not null,
  x_days int,
  initiation_date date not null,
  is_active boolean not null default true,
  created_by uuid references public.users(uid),
  created_at timestamptz not null default now()
);

create index on public.tasks (is_active);

create table public.task_instances (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  scheduled_date date not null,
  status task_status not null default 'upcoming',
  done_date date,
  remarks text,
  updated_by uuid references public.users(uid),
  updated_at timestamptz not null default now()
);

create index on public.task_instances (task_id, scheduled_date);
create index on public.task_instances (status, scheduled_date);

create table public.postponements (
  id uuid primary key default gen_random_uuid(),
  task_instance_id uuid not null references public.task_instances(id) on delete cascade,
  requested_by uuid not null references public.users(uid),
  reason text,
  requested_days int not null check (requested_days between 1 and 365),
  status post_status not null default 'pending',
  decided_by uuid references public.users(uid),
  decided_at timestamptz
);

create table public.audit_logs (
  id bigserial primary key,
  actor uuid,
  entity_type text,
  entity_id uuid,
  action text,
  meta jsonb,
  created_at timestamptz not null default now()
);

-- ============ HELPERS (fixed) ============
create or replace function public.next_due(d date, freq task_frequency, x int)
returns date
language sql immutable as $$
  select case
    when freq = 'daily'   then d + 1
    when freq = 'weekly'  then d + 7
    when freq = 'monthly' then
      (
        -- first day of next month as DATE
        (date_trunc('month', d) + interval '1 month')::date
        +
        -- add (desired day - 1), clamped to last day of next month
        (
          least(
            extract(day from d)::int,
            extract(day from (date_trunc('month', d) + interval '2 month - 1 day'))::int
          ) - 1
        )
      )
    when freq = 'after_x_days' then d + greatest(1, coalesce(x, 1))
  end
$$;

-- ============ TRIGGERS ============
-- On task insert: create the first instance from initiation_date
create or replace function public.create_first_instance()
returns trigger
language plpgsql security definer set search_path=public as $$
declare next_date date;
begin
  next_date := public.next_due(new.initiation_date, new.frequency, new.x_days);
  insert into public.task_instances (task_id, scheduled_date, status)
  values (new.id, next_date, case when next_date < current_date then 'overdue' else 'upcoming' end);
  return new;
end;$$;

drop trigger if exists on_task_insert on public.tasks;
create trigger on_task_insert after insert on public.tasks
for each row execute function public.create_first_instance();

-- When an instance is marked DONE, create the next instance
create or replace function public.on_instance_done_create_next()
returns trigger
language plpgsql security definer set search_path=public as $$
declare t record; next_date date;
begin
  if (new.status='done' and (old.status is distinct from 'done') and new.done_date is not null) then
    select * into t from public.tasks where id=new.task_id;
    if t.is_active then
      next_date := public.next_due(new.done_date, t.frequency, t.x_days);
      insert into public.task_instances (task_id, scheduled_date, status)
      values (t.id, next_date, case when next_date < current_date then 'overdue' else 'upcoming' end);
    end if;
  end if;
  return new;
end;$$;

drop trigger if exists on_instance_update on public.task_instances;
create trigger on_instance_update after update on public.task_instances
for each row execute function public.on_instance_done_create_next();

-- ============ RLS ============
alter table public.tasks           enable row level security;
alter table public.task_instances  enable row level security;
alter table public.postponements   enable row level security;
alter table public.audit_logs      enable row level security;

-- Tasks
drop policy if exists tasks_select_auth on public.tasks;
create policy tasks_select_auth on public.tasks
for select using ( public.is_authorized_uid(auth.uid()) );

drop policy if exists tasks_insert_admin on public.tasks;
create policy tasks_insert_admin on public.tasks
for insert with check ( public.is_admin_uid(auth.uid()) );

drop policy if exists tasks_update_admin on public.tasks;
create policy tasks_update_admin on public.tasks
for update using ( public.is_admin_uid(auth.uid()) ) with check ( true );

-- Task instances
drop policy if exists ti_select_auth on public.task_instances;
create policy ti_select_auth on public.task_instances
for select using ( public.is_authorized_uid(auth.uid()) );

drop policy if exists ti_update_admin on public.task_instances;
create policy ti_update_admin on public.task_instances
for update using ( public.is_admin_uid(auth.uid()) ) with check ( true );

-- Allow authorized users to issue updates (details enforced by trigger below)
drop policy if exists ti_update_user on public.task_instances;
create policy ti_update_user on public.task_instances
for update using ( public.is_authorized_uid(auth.uid()) )
with check ( public.is_authorized_uid(auth.uid()) );

-- Guard non-admin updates on task_instances:
-- Users may ONLY: change status to 'done', set done_date, edit remarks, updated_by/updated_at.
-- They may NOT: change task_id or scheduled_date.
create or replace function public.guard_task_instance_user_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_uid(auth.uid()) then
    -- immutable fields for non-admins
    if new.task_id <> old.task_id or new.scheduled_date <> old.scheduled_date then
      raise exception 'Only admins can change task_id or scheduled_date';
    end if;

    -- status can only be changed to DONE by users
    if new.status <> old.status and new.status <> 'done' then
      raise exception 'Users can only change status to DONE';
    end if;

    -- if marking DONE, require done_date
    if new.status = 'done' and new.done_date is null then
      raise exception 'done_date is required when marking DONE';
    end if;

    -- id must not change (defensive)
    if new.id <> old.id then
      raise exception 'Cannot change id';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_ti_user_update on public.task_instances;
create trigger trg_guard_ti_user_update
before update on public.task_instances
for each row
execute function public.guard_task_instance_user_update();

-- Postponements
drop policy if exists post_select_auth on public.postponements;
create policy post_select_auth on public.postponements
for select using ( public.is_authorized_uid(auth.uid()) );

drop policy if exists post_insert_user on public.postponements;
create policy post_insert_user on public.postponements
for insert with check ( public.is_authorized_uid(auth.uid()) );

drop policy if exists post_update_admin on public.postponements;
create policy post_update_admin on public.postponements
for update using ( public.is_admin_uid(auth.uid()) ) with check ( true );