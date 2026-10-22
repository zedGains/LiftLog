-- LiftLog: trainer profiles (bio, location, links, verified badge).
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql and moderation.sql to have been run first.

alter table public.profiles add column if not exists bio      text    not null default '';
alter table public.profiles add column if not exists location text    not null default '';
alter table public.profiles add column if not exists links    jsonb   not null default '{}'::jsonb;
alter table public.profiles add column if not exists verified boolean not null default false;

-- People can edit their own bio/location/links, but only an admin can set the verified badge.
create or replace function public.profiles_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    if tg_op = 'INSERT' then new.verified := false;
    else new.verified := old.verified; end if;
  end if;
  new.bio      := left(trim(coalesce(new.bio, '')), 600);
  new.location := left(trim(coalesce(new.location, '')), 80);
  if jsonb_typeof(new.links) <> 'object' then new.links := '{}'::jsonb; end if;
  new.links := (select coalesce(jsonb_object_agg(k, left(v #>> '{}', 200)), '{}'::jsonb)
                  from jsonb_each(new.links) e(k, v)
                 where k in ('instagram', 'youtube', 'website') and jsonb_typeof(v) = 'string');
  return new;
end $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before insert or update on public.profiles
  for each row execute function public.profiles_guard();

-- Setting someone's tier also sets their verified badge.
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
  update public.profiles set verified = new_tier in ('verified', 'pro') where id = u;
  return jsonb_build_object('ok', true, 'tier', new_tier);
end $$;
revoke all on function public.admin_set_tier(text, text) from public, anon;
grant execute on function public.admin_set_tier(text, text) to authenticated;

-- Backfill: anyone already verified/pro gets the badge.
alter table public.profiles disable trigger profiles_guard;
update public.profiles p set verified = true
  from public.creators c where c.user_id = p.id and c.tier in ('verified', 'pro') and not p.verified;
alter table public.profiles enable trigger profiles_guard;
