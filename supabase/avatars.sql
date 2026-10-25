-- LiftLog: profile pictures.
-- Paste into Supabase → SQL Editor → Run. Safe to run again. Needs schema.sql first.
--
-- Everyone picks what shows on their profile:
--   'crest' = initials inside their rank border (default)
--   'helm'  = their rank's warrior helm
--   'photo' = their own picture inside their rank border
-- Pictures are shrunk on the phone to a small square JPEG (about 5–10 KB) and stored here.

alter table public.profiles add column if not exists avatar      text not null default '';
alter table public.profiles add column if not exists avatar_mode text not null default 'crest';

create or replace function public.set_avatar(av text, mode text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  if mode not in ('crest', 'helm', 'photo') then raise exception 'bad mode'; end if;
  av := coalesce(av, '');
  if av <> '' and (av !~ '^data:image/(jpeg|webp|png);base64,[A-Za-z0-9+/=]+$' or length(av) > 60000) then
    raise exception 'bad image';
  end if;
  if mode = 'photo' and av = '' then raise exception 'no image'; end if;
  insert into public.profiles (id) values (auth.uid()) on conflict (id) do nothing;
  update public.profiles set avatar = av, avatar_mode = mode where id = auth.uid();
end $$;
revoke all on function public.set_avatar(text, text) from public, anon;
grant execute on function public.set_avatar(text, text) to authenticated;

-- Owner tool: remove someone's picture (for anything inappropriate).
create or replace function public.admin_clear_avatar(target uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  update public.profiles set avatar = '', avatar_mode = 'crest' where id = target;
end $$;
revoke all on function public.admin_clear_avatar(uuid) from public, anon;
grant execute on function public.admin_clear_avatar(uuid) to authenticated;
