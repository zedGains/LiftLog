-- LiftLog: custom exercises, friends' exercises, and suggestions for the shared library.
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql and friends.sql first.
--
-- How it works:
--  * Anyone can make their own exercise. Only they see it, plus their friends.
--  * They can suggest it for everyone's library. It waits for the owner (an admin) to approve it.
--  * Approved exercises show up in everyone's exercise list.

-- Each person's own exercises (mirrored here so friends can see them).
create table if not exists public.user_exercises (
  owner      uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.user_exercises enable row level security;   -- no policies: only the functions below touch it

create or replace function public._clean_exercise(e jsonb) returns jsonb
language sql immutable as $$
  select case when jsonb_typeof(e) = 'object' and length(trim(coalesce(e->>'name', ''))) between 2 and 60 then
    jsonb_build_object('id', left(coalesce(e->>'id', ''), 80), 'name', left(trim(e->>'name'), 60),
      'g', left(coalesce(e->>'g', 'Chest'), 20),
      'type', case when e->>'type' in ('lift', 'bw', 'cardio') then e->>'type' else 'lift' end)
  end
$$;

create or replace function public.set_my_exercises(items jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare clean jsonb;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if jsonb_typeof(items) <> 'array' then raise exception 'bad data'; end if;
  select coalesce(jsonb_agg(c), '[]'::jsonb) into clean
    from (select public._clean_exercise(e) c from jsonb_array_elements(items) e limit 300) t where c is not null;
  insert into public.user_exercises (owner, data, updated_at) values (auth.uid(), clean, now())
    on conflict (owner) do update set data = excluded.data, updated_at = now();
  return jsonb_array_length(clean);
end $$;
revoke all on function public.set_my_exercises(jsonb) from public, anon;
grant execute on function public.set_my_exercises(jsonb) to authenticated;

-- Exercises your friends made.
create or replace function public.friend_exercises() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('owner', ue.owner, 'name', coalesce(p.name, ''), 'items', ue.data)), '[]'::jsonb)
  from public.user_exercises ue left join public.profiles p on p.id = ue.owner
  where auth.uid() is not null and public.are_friends(ue.owner, auth.uid()) and jsonb_array_length(ue.data) > 0
$$;
revoke all on function public.friend_exercises() from public, anon;
grant execute on function public.friend_exercises() to authenticated;

-- Suggestions waiting for review, and the approved shared library.
create table if not exists public.exercise_submissions (
  id          bigint generated always as identity primary key,
  owner       uuid not null references auth.users(id) on delete cascade,
  name        text not null,
  grp         text not null,
  type        text not null,
  equip       text not null default '',
  note        text not null default '',
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz
);
create index if not exists exercise_submissions_status_idx on public.exercise_submissions (status);
alter table public.exercise_submissions enable row level security;

create table if not exists public.library_extra (
  id         text primary key,
  name       text not null unique,
  grp        text not null,
  type       text not null,
  equip      text not null default '',
  added_by   uuid,
  created_at timestamptz not null default now()
);
alter table public.library_extra enable row level security;

-- Returns 'sent', 'exists', 'pending' or 'limit'.
create or replace function public.submit_exercise(name text, grp text, type text, equip text default '', note text default '') returns text
language plpgsql security definer set search_path = public as $$
declare n text := left(trim(regexp_replace(coalesce(name, ''), '\s+', ' ', 'g')), 60);
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if length(n) < 2 then raise exception 'name too short'; end if;
  if type not in ('lift', 'bw', 'cardio') then type := 'lift'; end if;
  if exists (select 1 from public.library_extra where lower(library_extra.name) = lower(n)) then return 'exists'; end if;
  if exists (select 1 from public.exercise_submissions s where lower(s.name) = lower(n) and s.status = 'pending') then return 'pending'; end if;
  if (select count(*) from public.exercise_submissions s where s.owner = auth.uid() and s.status = 'pending') >= 10 then return 'limit'; end if;
  insert into public.exercise_submissions (owner, name, grp, type, equip, note)
    values (auth.uid(), n, left(coalesce(grp, 'Chest'), 20), type, left(coalesce(equip, ''), 30), left(coalesce(note, ''), 300));
  return 'sent';
end $$;
revoke all on function public.submit_exercise(text, text, text, text, text) from public, anon;
grant execute on function public.submit_exercise(text, text, text, text, text) to authenticated;

create or replace function public.library_extra_list() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'name', name, 'g', grp, 'type', type, 'eq', equip) order by name), '[]'::jsonb)
  from public.library_extra
$$;
revoke all on function public.library_extra_list() from public, anon;
grant execute on function public.library_extra_list() to authenticated;

-- Owner tools.
create or replace function public.admin_exercise_queue() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'g', s.grp, 'type', s.type, 'eq', s.equip,
            'note', s.note, 'by', coalesce(p.name, ''), 'at', s.created_at) order by s.created_at), '[]'::jsonb)
          from public.exercise_submissions s left join public.profiles p on p.id = s.owner where s.status = 'pending');
end $$;
revoke all on function public.admin_exercise_queue() from public, anon;
grant execute on function public.admin_exercise_queue() to authenticated;

-- Approve (optionally fixing the name or body part) or reject a suggestion.
create or replace function public.review_exercise(sid bigint, approve boolean, new_name text default null, new_grp text default null) returns text
language plpgsql security definer set search_path = public as $$
declare s public.exercise_submissions; n text; slugid text;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select * into s from public.exercise_submissions where id = sid and status = 'pending';
  if not found then return 'gone'; end if;
  if not approve then
    update public.exercise_submissions set status = 'rejected', reviewed_at = now() where id = sid;
    return 'rejected';
  end if;
  n := left(trim(coalesce(nullif(new_name, ''), s.name)), 60);
  slugid := 'x-' || trim(both '-' from regexp_replace(lower(n), '[^a-z0-9]+', '-', 'g'));
  insert into public.library_extra (id, name, grp, type, equip, added_by)
    values (slugid, n, coalesce(nullif(new_grp, ''), s.grp), s.type, s.equip, s.owner)
    on conflict do nothing;
  update public.exercise_submissions set status = 'approved', reviewed_at = now()
   where status = 'pending' and lower(name) = lower(s.name);
  return 'approved';
end $$;
revoke all on function public.review_exercise(bigint, boolean, text, text) from public, anon;
grant execute on function public.review_exercise(bigint, boolean, text, text) to authenticated;
