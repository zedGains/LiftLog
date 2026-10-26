-- LiftLog: friends.
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql, profiles.sql, leaderboard.sql and referrals.sql first.
--
-- How it works:
--  * Add a friend with their invite code, or from their profile on the leaderboard. They accept or decline.
--  * Friends see each other's week (days trained, streak) on a friends-only board. Never weights.
--  * Friends can share programs they made themselves with each other. Paid programs are never shared:
--    anything with a price above zero is dropped here on the server.

create table if not exists public.friendships (
  a          uuid not null references auth.users(id) on delete cascade,   -- always the smaller id
  b          uuid not null references auth.users(id) on delete cascade,
  requester  uuid not null,
  status     text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  primary key (a, b),
  check (a < b)
);
create index if not exists friendships_b_idx on public.friendships (b);
alter table public.friendships enable row level security;   -- no policies: only the functions below touch it

create or replace function public.are_friends(x uuid, y uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships where a = least(x, y) and b = greatest(x, y) and status = 'accepted')
$$;
revoke all on function public.are_friends(uuid, uuid) from public, anon, authenticated;

-- Returns 'sent', 'accepted', 'already', 'pending', 'self', 'unknown' or 'limit'.
create or replace function public.friend_request(code text default null, target uuid default null) returns text
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); who uuid := target; row public.friendships;
begin
  if me is null then raise exception 'not signed in'; end if;
  if who is null and code is not null then select id into who from public.profiles where ref_code = upper(trim(code)); end if;
  if who is null or not exists (select 1 from auth.users where id = who) then return 'unknown'; end if;
  if who = me then return 'self'; end if;
  select * into row from public.friendships where a = least(me, who) and b = greatest(me, who);
  if found then
    if row.status = 'accepted' then return 'already'; end if;
    if row.requester = me then return 'pending'; end if;
    update public.friendships set status = 'accepted' where a = row.a and b = row.b;   -- they asked first
    return 'accepted';
  end if;
  if (select count(*) from public.friendships where requester = me and status = 'pending') >= 50 then return 'limit'; end if;
  insert into public.friendships (a, b, requester) values (least(me, who), greatest(me, who), me);
  return 'sent';
end $$;
revoke all on function public.friend_request(text, uuid) from public, anon;
grant execute on function public.friend_request(text, uuid) to authenticated;

create or replace function public.friend_respond(other uuid, accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'not signed in'; end if;
  if accept then
    update public.friendships set status = 'accepted'
     where a = least(me, other) and b = greatest(me, other) and status = 'pending' and requester = other;
  else
    delete from public.friendships where a = least(me, other) and b = greatest(me, other) and status = 'pending' and requester = other;
  end if;
end $$;
revoke all on function public.friend_respond(uuid, boolean) from public, anon;
grant execute on function public.friend_respond(uuid, boolean) to authenticated;

-- Unfriend, or cancel a request you sent.
create or replace function public.friend_remove(other uuid) returns void
language sql security definer set search_path = public as $$
  delete from public.friendships where a = least(auth.uid(), other) and b = greatest(auth.uid(), other)
$$;
revoke all on function public.friend_remove(uuid) from public, anon;
grant execute on function public.friend_remove(uuid) to authenticated;

-- Friends and requests. Activity (days this week, last workout day, streak) only for accepted friends.
create or replace function public.my_friends() returns jsonb
language sql stable security definer set search_path = public as $$
  with mine as (
    select case when f.a = auth.uid() then f.b else f.a end as id, f.status, f.requester, f.created_at
    from public.friendships f where auth.uid() in (f.a, f.b)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', m.id, 'name', coalesce(p.name, ''),
      'state', case when m.status = 'accepted' then 'friend' when m.requester = auth.uid() then 'outgoing' else 'incoming' end,
      'thisWeek', case when m.status = 'accepted' then (select count(*) from public.checkins c where c.user_id = m.id
                    and c.day >= date_trunc('week', (now() at time zone 'utc')::date)::date) end,
      'lastDay', case when m.status = 'accepted' then (select max(day) from public.checkins c where c.user_id = m.id) end,
      'streak', case when m.status = 'accepted' then (public._board_stats(m.id)->>'streak')::int end
    ) order by m.status, p.name), '[]'::jsonb)
  from mine m left join public.profiles p on p.id = m.id
  where auth.uid() is not null
$$;
revoke all on function public.my_friends() from public, anon;
grant execute on function public.my_friends() to authenticated;

-- Friends-only board: you plus your friends, by full weeks in a row. Nobody needs to opt in or unlock.
create or replace function public.friends_board() returns jsonb
language sql stable security definer set search_path = public as $$
  with lb as (
    select p.id, p.name, (s->>'streak')::int streak, (s->>'last4')::int last4
    from public.profiles p cross join lateral (select public._board_stats(p.id) s) x
    where p.id = auth.uid() or public.are_friends(p.id, auth.uid())
  ), ranked as (select *, rank() over (order by streak desc, last4 desc) r from lb)
  select jsonb_build_object('rows', coalesce(jsonb_agg(jsonb_build_object('rank', r, 'id', id, 'name', coalesce(name, 'Lifter'),
           'streak', streak, 'last4', last4, 'me', id = auth.uid()) order by r, name), '[]'::jsonb), 'total', count(*))
  from ranked where auth.uid() is not null
$$;
revoke all on function public.friends_board() from public, anon;
grant execute on function public.friends_board() to authenticated;

-- Programs you made yourself, shared with friends only. Paid programs are stripped out.
create table if not exists public.friend_programs (
  owner      uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.friend_programs enable row level security;   -- no policies: only the functions below touch it

create or replace function public.set_friend_programs(progs jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare clean jsonb;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if jsonb_typeof(progs) <> 'array' then raise exception 'bad data'; end if;
  if length(progs::text) > 300000 then raise exception 'too big'; end if;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into clean from jsonb_array_elements(progs) e
   where jsonb_typeof(e) = 'object'
     and coalesce(nullif(e->>'price', '')::numeric, 0) <= 0
     and coalesce((e->>'paid')::boolean, false) = false
     and coalesce(e->>'from', '') = '';          -- only programs they made themselves, not copies of someone else's
  insert into public.friend_programs (owner, data, updated_at) values (auth.uid(), clean, now())
    on conflict (owner) do update set data = excluded.data, updated_at = now();
  return jsonb_array_length(clean);
end $$;
revoke all on function public.set_friend_programs(jsonb) from public, anon;
grant execute on function public.set_friend_programs(jsonb) to authenticated;

create or replace function public.friend_programs() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('owner', fp.owner, 'name', coalesce(p.name, ''), 'programs', fp.data)), '[]'::jsonb)
  from public.friend_programs fp left join public.profiles p on p.id = fp.owner
  where auth.uid() is not null and public.are_friends(fp.owner, auth.uid()) and jsonb_array_length(fp.data) > 0
$$;
revoke all on function public.friend_programs() from public, anon;
grant execute on function public.friend_programs() to authenticated;
