-- LiftLog: in-app "Send feedback".
-- Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Needs schema.sql to have been run first.

create table if not exists public.feedback (
  id         bigserial primary key,
  user_id    uuid references auth.users(id) on delete set null default auth.uid(),
  kind       text not null check (kind in ('bug', 'idea', 'confusing', 'other')),
  message    text not null,
  meta       jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  done       boolean not null default false
);
alter table public.feedback enable row level security;   -- no direct access; only through the functions below

-- Anyone signed in can send feedback (up to 20 messages a day).
create or replace function public.send_feedback(k text, m text, meta jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if k not in ('bug', 'idea', 'confusing', 'other') then raise exception 'bad kind'; end if;
  if length(trim(coalesce(m, ''))) < 3 then raise exception 'too short'; end if;
  if (select count(*) from public.feedback where user_id = auth.uid() and created_at > now() - interval '1 day') >= 20 then
    raise exception 'LIMIT' using errcode = 'P0001';
  end if;
  insert into public.feedback (user_id, kind, message, meta)
  values (auth.uid(), k, left(trim(m), 2000), case when jsonb_typeof(meta) = 'object' then meta else '{}'::jsonb end);
end $$;
revoke all on function public.send_feedback(text, text, jsonb) from public, anon;
grant execute on function public.send_feedback(text, text, jsonb) to authenticated;

-- Owner: open feedback, newest first, with who sent it so you can reply.
create or replace function public.admin_feedback() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', f.id, 'kind', f.kind, 'message', f.message, 'meta', f.meta, 'created_at', f.created_at,
      'name', p.name, 'email', u.email) order by f.created_at desc), '[]'::jsonb)
    into r
    from (select * from public.feedback where not done order by created_at desc limit 200) f
    left join public.profiles p on p.id = f.user_id
    left join auth.users u on u.id = f.user_id;
  return r;
end $$;
revoke all on function public.admin_feedback() from public, anon;
grant execute on function public.admin_feedback() to authenticated;

create or replace function public.resolve_feedback(fid bigint) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.feedback set done = true where id = fid;
end $$;
revoke all on function public.resolve_feedback(bigint) from public, anon;
grant execute on function public.resolve_feedback(bigint) to authenticated;
