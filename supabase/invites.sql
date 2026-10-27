-- LiftLog: invite link previews.
-- Paste into Supabase → SQL Editor → Run. Safe to run again. Needs referrals.sql first.
--
-- When someone opens their share screen, the app saves a small public "invite card"
-- (display name, rank points, level, badge count, streak). Anyone with that person's
-- invite code can read it, so links show a preview and the sign-up screen can say
-- "Zed invited you". Nothing else about the person is shown.

alter table public.profiles add column if not exists invite_card jsonb;

create or replace function public.set_invite_card(card jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if jsonb_typeof(card) <> 'object' or length(card::text) > 4000 then raise exception 'bad card'; end if;
  update public.profiles set invite_card = jsonb_build_object(
      'pts',    least(greatest(coalesce((card->>'pts')::int, 0), 0), 100000),
      'lvl',    least(greatest(coalesce((card->>'lvl')::int, 1), 1), 1000),
      'badges', least(greatest(coalesce((card->>'badges')::int, 0), 0), 1000),
      'streak', least(greatest(coalesce((card->>'streak')::int, 0), 0), 1000),
      'helm',   coalesce((card->>'helm')::boolean, false))
   where id = auth.uid();
end $$;
revoke all on function public.set_invite_card(jsonb) from public, anon;
grant execute on function public.set_invite_card(jsonb) to authenticated;

-- Public: what an invite link shows. Works without signing in.
create or replace function public.invite_card(code text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('name', coalesce(nullif(p.name, ''), 'A friend'), 'card', p.invite_card)
  from public.profiles p where p.ref_code = upper(trim(code)) limit 1
$$;
revoke all on function public.invite_card(text) from public;
grant execute on function public.invite_card(text) to anon, authenticated;
