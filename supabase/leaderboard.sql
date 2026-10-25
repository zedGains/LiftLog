-- LiftLog: consistency leaderboard.
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql (and profiles.sql) to have been run first.
--
-- Fair-play rules, all enforced here on the server:
--  * One check-in per person per day, recorded when they save a workout day.
--  * A check-in only counts for today (±1 day for time zones). Back-dated logs stay in history but don't count.
--  * A full week = 3+ workout days, Monday–Sunday.
--  * One rest pass a month: a finished week with 2 workouts still counts as full.
--  * The board unlocks after 2 full weeks in a row and stays unlocked.
--  * Score = full weeks in a row. The week in progress never breaks a streak.
--  * Only people who opted in are shown, by display name only. No weights.

create table if not exists public.checkins (
  user_id    uuid not null default auth.uid() references auth.users(id) on delete cascade,
  day        date not null,
  created_at timestamptz not null default now(),
  primary key (user_id, day)
);
alter table public.checkins enable row level security;
drop policy if exists checkins_self on public.checkins;
create policy checkins_self on public.checkins for select to authenticated using (user_id = auth.uid());
grant select on public.checkins to authenticated;

alter table public.profiles add column if not exists board boolean not null default false;

create or replace function public.checkin(d date) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if abs(d - (now() at time zone 'utc')::date) > 1 then return; end if;   -- only today counts
  insert into public.checkins (user_id, day) values (auth.uid(), d) on conflict do nothing;
end $$;
revoke all on function public.checkin(date) from public, anon;
grant execute on function public.checkin(date) to authenticated;

create or replace function public._board_stats(u uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  cur date := date_trunc('week', (now() at time zone 'utc')::date)::date;
  w date; first date; cnt int; full_wk boolean; run int := 0; unlocked boolean := false; used text[] := '{}';
  this_week int; last4 int;
begin
  select min(day) into first from public.checkins where user_id = u;
  select count(*) into this_week from public.checkins where user_id = u and day >= cur and day < cur + 7;
  select count(*) into last4 from public.checkins where user_id = u and day >= cur - 21 and day < cur + 7;
  if first is null then
    return jsonb_build_object('streak', 0, 'unlocked', false, 'thisWeek', 0, 'last4', 0, 'run', 0);
  end if;
  w := date_trunc('week', first)::date;
  while w <= cur loop
    select count(*) into cnt from public.checkins where user_id = u and day >= w and day < w + 7;
    full_wk := cnt >= 3;
    if not full_wk and cnt = 2 and w < cur and not (to_char(w, 'YYYY-MM') = any(used)) then
      full_wk := true; used := used || to_char(w, 'YYYY-MM');
    end if;
    if full_wk then run := run + 1; if run >= 2 then unlocked := true; end if;
    elsif w < cur then run := 0;
    end if;
    w := w + 7;
  end loop;
  return jsonb_build_object('streak', run, 'unlocked', unlocked, 'thisWeek', this_week, 'last4', last4,
    'passUsed', to_char(cur, 'YYYY-MM') = any(used));
end $$;
revoke all on function public._board_stats(uuid) from public, anon, authenticated;

create or replace function public.my_board_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select public._board_stats(auth.uid()) || jsonb_build_object('board', coalesce((select board from public.profiles where id = auth.uid()), false))
$$;
revoke all on function public.my_board_status() from public, anon;
grant execute on function public.my_board_status() to authenticated;

create or replace function public.set_board(on_board boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  update public.profiles set board = on_board where id = auth.uid();
end $$;
revoke all on function public.set_board(boolean) from public, anon;
grant execute on function public.set_board(boolean) to authenticated;

-- prog: a program key to rank only people using that program; null for everyone.
create or replace function public.leaderboard(prog text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with lb as (
    select p.id, p.name, (x.s->>'streak')::int streak, (x.s->>'last4')::int last4
    from public.profiles p
    cross join lateral (select public._board_stats(p.id) s) x
    where p.board and (x.s->>'unlocked')::boolean
      and (prog is null or exists (select 1 from public.docs d where d.path = 'social/' || p.id::text
                                    and jsonb_typeof(d.data->'uses') = 'array' and d.data->'uses' ? prog))
  ), ranked as (select *, rank() over (order by streak desc, last4 desc) r from lb),
  mine as (select public._board_stats(auth.uid()) m)
  select jsonb_build_object(
    'rows', coalesce((select jsonb_agg(jsonb_build_object('rank', r, 'name', coalesce(name, 'Lifter'), 'streak', streak,
             'last4', last4, 'me', id = auth.uid()) order by r, name) from (select * from ranked order by r limit 50) t), '[]'::jsonb),
    'total', (select count(*) from lb),
    'rank', (select r from ranked where id = auth.uid()),
    'pct', (select case when count(*) filter (where id <> auth.uid()) > 0 and (m->>'unlocked')::boolean
               then round(100.0 * count(*) filter (where id <> auth.uid() and
               (streak < (m->>'streak')::int or (streak = (m->>'streak')::int and last4 < (m->>'last4')::int)))
               / count(*) filter (where id <> auth.uid())) end from lb, mine group by m),
    'me', (select m from mine))
  where auth.uid() is not null
$$;
revoke all on function public.leaderboard(text) from public, anon;
grant execute on function public.leaderboard(text) to authenticated;
