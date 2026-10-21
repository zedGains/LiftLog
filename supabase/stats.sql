-- LiftLog stats. Paste into Supabase → SQL Editor → Run. Safe to run again.
-- Both functions return COUNTS ONLY — never anyone's individual logs, names of followers, or weights.

-- Every finished workout session (one row per person per day logged), from the private log documents.
create or replace view public._sessions with (security_invoker = true) as
select d.owner, (e->>'date')::date as day, e->>'day' as day_key, e->>'name' as name
from public.docs d
cross join lateral jsonb_array_elements(case when jsonb_typeof(d.data->'entries') = 'array' then d.data->'entries' else '[]'::jsonb end) e
where d.col like 'data/users/%'
  and d.path !~ '/_(plan|template)$'
  and coalesce(e->>'date','') ~ '^\d{4}-\d{2}-\d{2}$'
  and coalesce((e->>'done')::boolean, true);
revoke all on public._sessions from anon, authenticated;

-- Owner dashboard (admins only).
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare r jsonb;
begin
  if not public.is_admin() then raise exception 'not allowed'; end if;
  with sess as (select distinct owner, day from public._sessions),
  ex as (select name, count(*) n from public._sessions where day > current_date - 30 and name is not null group by name),
  plans as (select owner, data from public.docs where path ~ '^data/users/[^/]+/_plan$'),
  prog as (select split_part(d.path,'/',2) as author, p->>'id' as id, p->>'title' as title
           from public.docs d cross join lateral jsonb_array_elements(case when jsonb_typeof(d.data->'programs')='array' then d.data->'programs' else '[]'::jsonb end) p
           where d.col = 'programs'),
  soc as (select data from public.docs where col = 'social'),
  uses as (select u #>> '{}' as k from soc cross join lateral jsonb_array_elements(case when jsonb_typeof(data->'uses')='array' then data->'uses' else '[]'::jsonb end) u),
  likes as (select u #>> '{}' as k from soc cross join lateral jsonb_array_elements(case when jsonb_typeof(data->'likes')='array' then data->'likes' else '[]'::jsonb end) u)
  select jsonb_build_object(
    'users',      (select count(*) from auth.users),
    'new7',       (select count(*) from auth.users where created_at > now() - interval '7 days'),
    'new30',      (select count(*) from auth.users where created_at > now() - interval '30 days'),
    'active7',    (select count(distinct owner) from sess where day > current_date - 7),
    'active30',   (select count(distinct owner) from sess where day > current_date - 30),
    'workouts30', (select count(*) from sess where day > current_date - 30),
    'workoutsAll',(select count(*) from sess),
    'loggedAny',  (select count(distinct owner) from sess),
    'returned',   (select count(*) from (select owner from sess group by owner having max(day) - min(day) >= 7) x),
    'weekly',     (select coalesce(jsonb_agg(jsonb_build_object('week', wk, 'n', n, 'people', p) order by wk), '[]'::jsonb)
                   from (select date_trunc('week', day)::date wk, count(*) n, count(distinct owner) p from sess
                         where day >= date_trunc('week', current_date)::date - 49 group by 1) w),
    'signupsWeekly',(select coalesce(jsonb_agg(jsonb_build_object('week', wk, 'n', n) order by wk), '[]'::jsonb)
                   from (select date_trunc('week', created_at)::date wk, count(*) n from auth.users
                         where created_at >= date_trunc('week', now()) - interval '49 days' group by 1) s),
    'starts',     (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(data->>'template', 'private') k, count(*) n from plans group by 1) s),
    'topExercises',(select coalesce(jsonb_agg(jsonb_build_object('name', name, 'n', n) order by n desc), '[]'::jsonb) from (select * from ex order by n desc limit 10) t),
    'partnerUsers',(select count(*) from plans where jsonb_typeof(data->'partners')='array' and jsonb_array_length(data->'partners') > 0),
    'units',      (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select coalesce(data->>'units', 'default') k, count(*) n from plans group by 1) u),
    'programs',   (select count(*) from prog),
    'following',  (select count(*) from uses),
    'topPrograms',(select coalesce(jsonb_agg(jsonb_build_object('title', title, 'author', author, 'using', u, 'likes', l) order by u desc, l desc), '[]'::jsonb) from (
                     select prog.title, coalesce(pr.name, '') as author,
                       (select count(*) from uses  where k = prog.author || ':' || prog.id) as u,
                       (select count(*) from likes where k = prog.author || ':' || prog.id) as l
                     from prog left join public.profiles pr on pr.id::text = prog.author
                     order by u desc, l desc limit 10) z)
  ) into r;
  return r;
end $$;
revoke all on function public.admin_stats() from public, anon;
grant execute on function public.admin_stats() to authenticated;

-- A creator's stats for the programs THEY published (counts only).
create or replace function public.my_program_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare me text := auth.uid()::text; r jsonb;
begin
  if me is null then raise exception 'not signed in'; end if;
  with prog as (select p->>'id' as id, p->>'title' as title, p->>'id' as id2
                from public.docs d cross join lateral jsonb_array_elements(case when jsonb_typeof(d.data->'programs')='array' then d.data->'programs' else '[]'::jsonb end) p
                where d.path = 'programs/' || me),
  soc as (select owner, data from public.docs where col = 'social' and owner::text <> me),
  uses as (select u #>> '{}' as k from soc cross join lateral jsonb_array_elements(case when jsonb_typeof(data->'uses')='array' then data->'uses' else '[]'::jsonb end) u),
  likes as (select u #>> '{}' as k from soc cross join lateral jsonb_array_elements(case when jsonb_typeof(data->'likes')='array' then data->'likes' else '[]'::jsonb end) u),
  starts as (select s.key as k, to_timestamp((s.value #>> '{}')::double precision / 1000) as at
             from soc cross join lateral jsonb_each(case when jsonb_typeof(data->'started')='object' then data->'started' else '{}'::jsonb end) s
             where (s.value #>> '{}') ~ '^\d+(\.\d+)?$'),
  followers as (select owner, data->'activeProgram'->>'key' as k from public.docs where path ~ '^data/users/[^/]+/_plan$' and owner::text <> me),
  fsess as (select distinct f.k, s.owner, s.day from followers f join public._sessions s on s.owner = f.owner
            where s.day > current_date - 30 and coalesce(s.day_key,'') like 'pw%')
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', prog.id, 'title', prog.title,
      'using',   (select count(*) from uses  where k = me || ':' || prog.id),
      'likes',   (select count(*) from likes where k = me || ':' || prog.id),
      'started', (select count(*) from starts where k = me || ':' || prog.id),
      'workouts30', (select count(*) from fsess where k = me || ':' || prog.id),
      'startsWeekly', (select coalesce(jsonb_agg(jsonb_build_object('week', wk, 'n', n) order by wk), '[]'::jsonb)
                       from (select date_trunc('week', at)::date wk, count(*) n from starts
                             where k = me || ':' || prog.id and at >= date_trunc('week', now()) - interval '49 days' group by 1) w),
      'sales', 0, 'revenueCents', 0
    ) order by prog.title), '[]'::jsonb) into r
  from prog;
  return r;
end $$;
revoke all on function public.my_program_stats() from public, anon;
grant execute on function public.my_program_stats() to authenticated;
