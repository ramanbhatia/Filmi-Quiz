-- Filmi Flashback: Mehfils (share the exact tape you just played; friends play it and compare).
-- Paste into Supabase > SQL Editor > New query, then Run. Safe to run more than once.
-- Needs protection-setup.sql to have been run first (_rate_check, _clean_label).
-- Tables are private: the app only reads and writes them through the functions below.

create table if not exists public.mehfils (
  code         text primary key check (code ~ '^[A-Z2-9]{6}$'),
  starter_name text not null,
  starter_city text not null,
  name_key     text not null,
  city_key     text not null,
  era          text not null check (era in ('gold','80s','90s','00s','10s','all')),
  mode         text not null check (mode in ('mix','film','singer','actor')),
  clip_len     int  not null check (clip_len between 3 and 30),
  n            int  not null check (n between 1 and 20),
  questions    jsonb not null,   -- [{id, kind, prompt, options[], answer, offset}] in play order
  created_at   timestamptz not null default now(),
  expires_at   timestamptz not null default now() + interval '30 days'
);
create index if not exists mehfils_starter on public.mehfils (name_key, city_key);

create table if not exists public.mehfil_plays (
  code      text not null references public.mehfils(code) on delete cascade,
  name      text not null,
  city      text not null,
  name_key  text not null,
  city_key  text not null,
  score     int  not null check (score >= 0),
  results   text not null,      -- one letter per question: C correct, W wrong, S skipped, X couldn't load
  played_at timestamptz not null default now(),
  primary key (code, name_key, city_key)
);
create index if not exists mehfil_plays_player on public.mehfil_plays (name_key, city_key);

alter table public.mehfils      enable row level security;
alter table public.mehfil_plays enable row level security;
revoke all on public.mehfils, public.mehfil_plays from anon, authenticated;

-- One Mehfil with its questions and everyone's results (null if missing or expired).
create or replace function public.get_mehfil(p_code text)
returns json
language sql stable security definer set search_path = public as $$
  select json_build_object(
    'code', m.code, 'era', m.era, 'mode', m.mode, 'clip_len', m.clip_len, 'n', m.n,
    'questions', m.questions, 'starter_name', m.starter_name, 'starter_city', m.starter_city,
    'created_at', m.created_at, 'expires_at', m.expires_at,
    'plays', (select coalesce(json_agg(json_build_object('name', p.name, 'city', p.city, 'score', p.score,
                                                         'results', p.results, 'played_at', p.played_at)
                                       order by p.score desc, p.played_at asc), '[]'::json)
              from mehfil_plays p where p.code = m.code))
  from mehfils m
  where m.code = upper(trim(p_code)) and m.expires_at > now();
$$;

-- Start a Mehfil from the game just played. Returns the new code.
create or replace function public.create_mehfil(
  p_name text, p_city text, p_era text, p_mode text, p_len int, p_questions jsonb, p_results text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_n    int;
  v_q    jsonb;
  v_code text;
  v_abc  text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  i      int;
begin
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  if p_questions is null or jsonb_typeof(p_questions) <> 'array' or length(p_questions::text) > 30000 then
    raise exception 'invalid mehfil';
  end if;
  v_n := jsonb_array_length(p_questions);
  if v_n < 1 or v_n > 20 or p_results is null or length(p_results) <> v_n or p_results !~ '^[CWS]+$'
     or p_era not in ('gold','80s','90s','00s','10s','all') or p_mode not in ('mix','film','singer','actor')
     or p_len is null or p_len not between 3 and 30 then
    raise exception 'invalid mehfil';
  end if;
  for v_q in select * from jsonb_array_elements(p_questions) loop
    if jsonb_typeof(v_q) <> 'object'
       or jsonb_typeof(v_q->'id') <> 'number' or (v_q->>'id')::numeric <= 0
       or coalesce(v_q->>'kind', '') not in ('film','singer','actor')
       or coalesce(char_length(v_q->>'prompt'), 0) not between 1 and 120
       or jsonb_typeof(v_q->'options') <> 'array' or jsonb_array_length(v_q->'options') not between 2 and 4
       or exists (select 1 from jsonb_array_elements(v_q->'options') o
                  where jsonb_typeof(o) <> 'string' or char_length(o #>> '{}') not between 1 and 120)
       or not (v_q->'options') @> jsonb_build_array(v_q->>'answer')
       or jsonb_typeof(v_q->'offset') <> 'number' or (v_q->>'offset')::numeric not between 0 and 60 then
      raise exception 'invalid mehfil';
    end if;
  end loop;

  perform _rate_check('mehfil', lower(trim(p_name)) || '|' || lower(trim(p_city)), 20, interval '1 hour');
  perform _rate_check('mehfil', 'all', 300, interval '1 hour');

  delete from mehfils where expires_at < now() - interval '7 days';   -- tidy up old ones

  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_abc, 1 + floor(random() * length(v_abc))::int, 1);
    end loop;
    exit when not exists (select 1 from mehfils where code = v_code);
  end loop;

  insert into mehfils (code, starter_name, starter_city, name_key, city_key, era, mode, clip_len, n, questions)
  values (v_code, trim(p_name), trim(p_city), lower(trim(p_name)), lower(trim(p_city)),
          p_era, p_mode, p_len, v_n, p_questions);
  insert into mehfil_plays (code, name, city, name_key, city_key, score, results)
  values (v_code, trim(p_name), trim(p_city), lower(trim(p_name)), lower(trim(p_city)),
          length(p_results) - length(replace(p_results, 'C', '')), p_results);
  return v_code;
end $$;

-- A friend's result on a Mehfil (their first play counts). Returns the Mehfil with everyone's results.
create or replace function public.play_mehfil(p_code text, p_name text, p_city text, p_results text)
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_n int;
begin
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  select n into v_n from mehfils where code = upper(trim(p_code)) and expires_at > now();
  if v_n is null then raise exception 'mehfil not found'; end if;
  if p_results is null or length(p_results) <> v_n or p_results !~ '^[CWSX]+$' then
    raise exception 'invalid mehfil';
  end if;
  perform _rate_check('mehfil_play', lower(trim(p_name)) || '|' || lower(trim(p_city)), 60, interval '1 hour');
  perform _rate_check('mehfil_play', 'all', 1000, interval '1 hour');

  insert into mehfil_plays (code, name, city, name_key, city_key, score, results)
  values (upper(trim(p_code)), trim(p_name), trim(p_city), lower(trim(p_name)), lower(trim(p_city)),
          length(p_results) - length(replace(p_results, 'C', '')), p_results)
  on conflict (code, name_key, city_key) do nothing;
  return get_mehfil(p_code);
end $$;

-- Every live Mehfil a player started or played, newest activity first.
create or replace function public.my_mehfils(p_name text, p_city text)
returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(to_json(x) order by x.last_activity desc), '[]'::json)
  from (
    select m.code, m.era, m.n, m.starter_name, m.starter_city, m.created_at, m.expires_at,
           (m.name_key = lower(trim(p_name)) and m.city_key = lower(trim(p_city))) as mine,
           (select count(*) from mehfil_plays p where p.code = m.code) as plays_count,
           (select json_build_object('name', p.name, 'city', p.city, 'score', p.score)
              from mehfil_plays p where p.code = m.code order by p.score desc, p.played_at asc limit 1) as top,
           (select count(*) from mehfil_plays p where p.code = m.code
              and p.score = (select max(q.score) from mehfil_plays q where q.code = m.code)) as top_count,
           (select p.score from mehfil_plays p where p.code = m.code
              and p.name_key = lower(trim(p_name)) and p.city_key = lower(trim(p_city))) as my_score,
           (select max(p.played_at) from mehfil_plays p where p.code = m.code) as last_activity
    from mehfils m
    where m.expires_at > now()
      and m.code in (select code from mehfil_plays
                     where name_key = lower(trim(p_name)) and city_key = lower(trim(p_city)))
    order by last_activity desc
    limit 50
  ) x;
$$;

revoke all on function public.get_mehfil(text) from public;
revoke all on function public.create_mehfil(text, text, text, text, int, jsonb, text) from public;
revoke all on function public.play_mehfil(text, text, text, text) from public;
revoke all on function public.my_mehfils(text, text) from public;
grant execute on function public.get_mehfil(text) to anon, authenticated;
grant execute on function public.create_mehfil(text, text, text, text, int, jsonb, text) to anon, authenticated;
grant execute on function public.play_mehfil(text, text, text, text) to anon, authenticated;
grant execute on function public.my_mehfils(text, text) to anon, authenticated;
