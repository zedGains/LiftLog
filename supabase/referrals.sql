-- LiftLog: invite links and referral badges.
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql, profiles.sql and leaderboard.sql first.
--
-- Fair-play rules, enforced here:
--  * Everyone gets one invite code. Links look like  https://<app>/?ref=CODE
--  * Only a brand-new account (made in the last 7 days) can claim a code, once, and not its own.
--  * A friend only counts toward badges after they finish their first full week
--    (3 workout days saved on the day, from leaderboard check-ins). Fake sign-ups never count.

alter table public.profiles add column if not exists ref_code text;
create unique index if not exists profiles_ref_code_idx on public.profiles (ref_code);

create table if not exists public.referrals (
  referred   uuid primary key references auth.users(id) on delete cascade,
  referrer   uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create index if not exists referrals_referrer_idx on public.referrals (referrer);
alter table public.referrals enable row level security;   -- no policies: only the functions below touch it

create or replace function public.my_ref_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text; tries int := 0;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select ref_code into c from public.profiles where id = auth.uid();
  if c is not null then return c; end if;
  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;
  loop
    c := (select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, 6));
    begin
      update public.profiles set ref_code = c where id = auth.uid() and ref_code is null;
      return (select ref_code from public.profiles where id = auth.uid());
    exception when unique_violation then
      tries := tries + 1; if tries > 10 then raise; end if;
    end;
  end loop;
end $$;
revoke all on function public.my_ref_code() from public, anon;
grant execute on function public.my_ref_code() to authenticated;

-- Returns 'ok', 'own', 'used', 'old' or 'unknown'.
create or replace function public.claim_referral(code text) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); who uuid; made timestamptz;
begin
  if me is null then raise exception 'not signed in'; end if;
  select id into who from public.profiles where ref_code = upper(trim(code));
  if who is null then return 'unknown'; end if;
  if who = me then return 'own'; end if;
  if exists (select 1 from public.referrals where referred = me) then return 'used'; end if;
  select created_at into made from auth.users where id = me;
  if made < now() - interval '7 days' then return 'old'; end if;
  insert into public.referrals (referred, referrer) values (me, who) on conflict do nothing;
  return 'ok';
end $$;
revoke all on function public.claim_referral(text) from public, anon;
grant execute on function public.claim_referral(text) to authenticated;

create or replace function public.my_referrals() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'code', (select ref_code from public.profiles where id = auth.uid()),
    'joined', (select count(*) from public.referrals where referrer = auth.uid()),
    'active', (select count(*) from public.referrals r where r.referrer = auth.uid()
                 and (select count(*) from public.checkins c where c.user_id = r.referred) >= 3))
  where auth.uid() is not null
$$;
revoke all on function public.my_referrals() from public, anon;
grant execute on function public.my_referrals() to authenticated;
