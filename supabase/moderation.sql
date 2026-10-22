-- LiftLog: publishing rules, copy protection and reports.
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql and stats.sql to have been run first.

-- ===== Creator tiers =====
-- free: 2 published programs · verified / pro: 25 · admins: unlimited
create table if not exists public.creators (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  tier       text not null default 'free' check (tier in ('free', 'verified', 'pro')),
  updated_at timestamptz not null default now()
);
alter table public.creators enable row level security;
drop policy if exists creators_self on public.creators;
create policy creators_self on public.creators for select to authenticated using (user_id = auth.uid());

create or replace function public._tier(u uuid) returns text
language sql stable security definer set search_path = public as
$$ select coalesce((select tier from public.creators where user_id = u), 'free') $$;

create or replace function public._limit(u uuid) returns int
language sql stable security definer set search_path = public as
$$ select case when exists (select 1 from public.admins where user_id = u) then 1000
               when public._tier(u) in ('verified', 'pro') then 25 else 2 end $$;

-- New accounts must be 3+ days old or have logged 3+ workouts before publishing.
create or replace function public._can_publish(u uuid) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from public.admins where user_id = u)
       or public._tier(u) in ('verified', 'pro')
       or (select created_at < now() - interval '3 days' from auth.users where id = u)
       or (select count(*) >= 3 from (select distinct day from public._sessions where owner = u) s) $$;

-- Exercise names in a program (all weeks), lower-cased, for duplicate checks.
create or replace function public._prog_ex(p jsonb) returns text[]
language sql immutable as
$$ select coalesce(array_agg(distinct lower(i->>'name')), '{}')
   from jsonb_array_elements(case when jsonb_typeof(p->'weeks') = 'array' then p->'weeks' else '[]'::jsonb end) w
   cross join lateral jsonb_each(case when jsonb_typeof(w->'days') = 'object' then w->'days' else '{}'::jsonb end) d
   cross join lateral jsonb_array_elements(case when jsonb_typeof(d.value->'items') = 'array' then d.value->'items' else '[]'::jsonb end) i
   where coalesce(i->>'name', '') <> '' $$;

-- ===== Rules checked every time someone publishes =====
create or replace function public.check_programs() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  progs jsonb := case when jsonb_typeof(new.data->'programs') = 'array' then new.data->'programs' else '[]'::jsonb end;
  old_ids text[] := '{}';
  n int; lim int; p jsonb; ex text[]; w0 jsonb; days_used int; ex_count int; q record; qex text[]; inter int; uni int;
begin
  if new.col <> 'programs' then return new; end if;
  -- an admin removing someone else's program is moderation, not publishing
  if me is not null and public.is_admin() and new.path <> 'programs/' || me::text then return new; end if;

  if tg_op = 'UPDATE' and jsonb_typeof(old.data->'programs') = 'array' then
    old_ids := array(select x->>'id' from jsonb_array_elements(old.data->'programs') x);
  end if;

  n := jsonb_array_length(progs);
  lim := public._limit(new.owner);
  if n > lim and n > coalesce(array_length(old_ids, 1), 0) then
    raise exception 'LIMIT:%', lim using errcode = 'P0001';
  end if;

  for p in select x from jsonb_array_elements(progs) x loop
    if (p->>'id') = any(old_ids) then continue; end if;   -- only newly published programs are checked

    if not public._can_publish(new.owner) then
      raise exception 'NEW_ACCOUNT' using errcode = 'P0001';
    end if;

    w0 := coalesce(p->'weeks'->0->'days', '{}'::jsonb);
    select count(*) filter (where jsonb_typeof(v->'items') = 'array' and jsonb_array_length(v->'items') > 0),
           coalesce(sum(case when jsonb_typeof(v->'items') = 'array' then jsonb_array_length(v->'items') else 0 end), 0)
      into days_used, ex_count
      from jsonb_each(case when jsonb_typeof(w0) = 'object' then w0 else '{}'::jsonb end) as e(k, v);
    if length(trim(coalesce(p->>'title', ''))) < 3
       or length(trim(coalesce(p->>'desc', ''))) < 40
       or days_used < 2 or ex_count < 6 then
      raise exception 'CONTENT' using errcode = 'P0001';
    end if;

    -- near-copies of someone else's program are refused, unless they allowed copying and this is that copy
    ex := public._prog_ex(p);
    if coalesce(array_length(ex, 1), 0) >= 6 then
      for q in
        select split_part(d.path, '/', 2) as author, x as prog
        from public.docs d cross join lateral jsonb_array_elements(case when jsonb_typeof(d.data->'programs') = 'array' then d.data->'programs' else '[]'::jsonb end) x
        where d.col = 'programs' and d.path <> new.path
      loop
        if coalesce((q.prog->>'allowCopy')::boolean, false) and p->>'from' = q.author || ':' || (q.prog->>'id') then continue; end if;
        qex := public._prog_ex(q.prog);
        select count(*) into inter from unnest(ex) a where a = any(qex);
        uni := coalesce(array_length(ex, 1), 0) + coalesce(array_length(qex, 1), 0) - inter;
        if uni > 0 and inter::numeric / uni >= 0.85 then
          raise exception 'SIMILAR:%', coalesce(q.prog->>'title', 'another program') using errcode = 'P0001';
        end if;
      end loop;
    end if;
  end loop;
  return new;
end $$;

drop trigger if exists docs_check_programs on public.docs;
create trigger docs_check_programs before insert or update on public.docs
  for each row when (new.col = 'programs') execute function public.check_programs();

-- What the app shows a creator: tier, limit, how many are published, whether they can publish yet.
create or replace function public.my_creator_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'tier', public._tier(auth.uid()),
    'limit', public._limit(auth.uid()),
    'published', coalesce((select jsonb_array_length(data->'programs') from public.docs where path = 'programs/' || auth.uid()::text and jsonb_typeof(data->'programs') = 'array'), 0),
    'canPublish', public._can_publish(auth.uid()))
$$;
revoke all on function public.my_creator_status() from public, anon;
grant execute on function public.my_creator_status() to authenticated;

-- Owner tool: set someone's tier by email ('free', 'verified' or 'pro').
create or replace function public.admin_set_tier(target_email text, new_tier text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  if new_tier not in ('free', 'verified', 'pro') then raise exception 'bad tier'; end if;
  select id into u from auth.users where lower(email) = lower(trim(target_email));
  if u is null then return jsonb_build_object('ok', false, 'error', 'No account with that email'); end if;
  insert into public.creators (user_id, tier, updated_at) values (u, new_tier, now())
    on conflict (user_id) do update set tier = excluded.tier, updated_at = now();
  return jsonb_build_object('ok', true, 'tier', new_tier);
end $$;
revoke all on function public.admin_set_tier(text, text) from public, anon;
grant execute on function public.admin_set_tier(text, text) to authenticated;

-- ===== Reports =====
create table if not exists public.reports (
  id          bigserial primary key,
  reporter    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  program_key text not null,
  reason      text not null,
  note        text,
  created_at  timestamptz not null default now(),
  unique (reporter, program_key)
);
alter table public.reports enable row level security;   -- no direct access; only through the functions below

create or replace function public.report_program(k text, r text, n text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if r not in ('Spam', 'Copied from someone else', 'Unsafe or harmful', 'Offensive', 'Other') then raise exception 'bad reason'; end if;
  insert into public.reports (reporter, program_key, reason, note) values (auth.uid(), left(k, 200), r, left(n, 500))
    on conflict (reporter, program_key) do update set reason = excluded.reason, note = excluded.note, created_at = now();
end $$;
revoke all on function public.report_program(text, text, text) from public, anon;
grant execute on function public.report_program(text, text, text) to authenticated;

create or replace function public.admin_reports() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(t order by (t->>'count')::int desc, t->>'latest' desc), '[]'::jsonb) into r from (
    select jsonb_build_object(
      'key', rp.program_key, 'count', count(*), 'latest', max(rp.created_at),
      'reasons', jsonb_agg(distinct rp.reason),
      'notes', coalesce(jsonb_agg(rp.note) filter (where coalesce(rp.note, '') <> ''), '[]'::jsonb),
      'title', (select x->>'title' from public.docs d cross join lateral jsonb_array_elements(d.data->'programs') x
                where d.path = 'programs/' || split_part(rp.program_key, ':', 1) and x->>'id' = split_part(rp.program_key, ':', 2) limit 1),
      'author', (select name from public.profiles where id::text = split_part(rp.program_key, ':', 1))
    ) t
    from public.reports rp group by rp.program_key) z;
  return r;
end $$;
revoke all on function public.admin_reports() from public, anon;
grant execute on function public.admin_reports() to authenticated;

create or replace function public.dismiss_reports(k text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  delete from public.reports where program_key = k;
end $$;
revoke all on function public.dismiss_reports(text) from public, anon;
grant execute on function public.dismiss_reports(text) to authenticated;
