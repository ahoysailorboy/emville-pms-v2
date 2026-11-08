-- Enable useful extensions
create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";

-- 1) Enums (keep them small & reusable)
create type user_role as enum ('admin','user');

-- 2) Users profile table (mirrors auth.users)
create table if not exists public.users (
  uid uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  full_name text,
  role user_role not null default 'user',
  is_authorized boolean not null default false,
  created_at timestamptz not null default now()
);

-- 3) Helper functions (auth checks)
create or replace function public.is_authorized_uid(u uuid)
returns boolean
language sql
stable
as $$
  select coalesce((select is_authorized from public.users where uid = u), false)
$$;

create or replace function public.is_admin_uid(u uuid)
returns boolean
language sql
stable
as $$
  select coalesce((select role = 'admin' from public.users where uid = u), false)
$$;

-- 4) On new auth user → insert a public.users row
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (uid, email, full_name, role, is_authorized)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    'user',
    false
  )
  on conflict (uid) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute function public.handle_new_auth_user();

-- 5) RLS on users
alter table public.users enable row level security;

-- a) Users can read their own row; admins can read all
drop policy if exists users_select_self on public.users;
create policy users_select_self
on public.users
for select
using ( auth.uid() = uid or public.is_admin_uid(auth.uid()) );

-- b) Only admins can update any users row (for role/authorization management)
drop policy if exists users_update_admin on public.users;
create policy users_update_admin
on public.users
for update
using ( public.is_admin_uid(auth.uid()) )
with check ( true );

-- (Optional) Allow a user to update just their own full_name (not role/is_authorized).
-- Keep it commented for now; we’ll decide later.
-- create policy users_update_self_profile
-- on public.users
-- for update
-- using ( auth.uid() = uid )
-- with check ( auth.uid() = uid and (role is distinct from 'admin') );