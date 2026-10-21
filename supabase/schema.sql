-- LiftLog database setup. Paste this whole file into Supabase → SQL Editor → Run.
-- Safe to run more than once.

-- One row per document. path = "<collection>/<doc id>", col = "<collection>".
create table if not exists public.docs (
  path        text primary key,
  col         text not null,
  owner       uuid not null default auth.uid() references auth.users(id) on delete cascade,
  data        jsonb not null,
  updated_at  timestamptz not null default now()
);
create index if not exists docs_col_idx on public.docs (col);
alter table public.docs replica identity full;   -- realtime delete events carry the path
alter table public.docs enable row level security;

-- Display names shown on shared programs.
create table if not exists public.profiles (
  id    uuid primary key references auth.users(id) on delete cascade,
  name  text not null default ''
);
alter table public.profiles enable row level security;

-- People who can moderate the community (remove programs). Add yourself by hand (see README).
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

-- Which paths a person may write: their own private data, plus their own
-- programs/<id> and social/<id> documents. Admins may also write any programs/social doc.
create or replace function public.can_write(p text) returns boolean
language sql stable as
$$ select auth.uid() is not null and (
     p like 'data/users/' || auth.uid()::text || '/%'
     or p = 'programs/' || auth.uid()::text
     or p = 'social/'   || auth.uid()::text
     or ((p like 'programs/%' or p like 'social/%') and public.is_admin())
   ) $$;

drop policy if exists docs_read   on public.docs;
drop policy if exists docs_insert on public.docs;
drop policy if exists docs_update on public.docs;
drop policy if exists docs_delete on public.docs;

-- Read: your own documents, plus the shared community collections.
create policy docs_read on public.docs for select to authenticated
  using (owner = auth.uid() or col in ('programs', 'social'));

create policy docs_insert on public.docs for insert to authenticated
  with check (public.can_write(path) and col = regexp_replace(path, '/[^/]+$', '')
              and (owner = auth.uid() or public.is_admin()));

create policy docs_update on public.docs for update to authenticated
  using (public.can_write(path))
  with check (public.can_write(path) and col = regexp_replace(path, '/[^/]+$', ''));

create policy docs_delete on public.docs for delete to authenticated
  using (public.can_write(path));

-- Owner can never be changed on update.
create or replace function public.docs_keep_owner() returns trigger
language plpgsql as $$ begin new.owner := old.owner; return new; end $$;
drop trigger if exists docs_keep_owner on public.docs;
create trigger docs_keep_owner before update on public.docs
  for each row execute function public.docs_keep_owner();

drop policy if exists profiles_read  on public.profiles;
drop policy if exists profiles_write on public.profiles;
drop policy if exists profiles_upd   on public.profiles;
create policy profiles_read  on public.profiles for select to authenticated using (true);
create policy profiles_write on public.profiles for insert to authenticated with check (id = auth.uid());
create policy profiles_upd   on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists admins_self on public.admins;
create policy admins_self on public.admins for select to authenticated using (user_id = auth.uid());

-- Live updates for the app.
do $$ begin
  alter publication supabase_realtime add table public.docs;
exception when duplicate_object then null; end $$;
