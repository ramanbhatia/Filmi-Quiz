-- Filmi Flashback: decade titles (Walkman Rookie, T-Series Collector, ...)
-- Keeps each player's songs played and correct answers per decade, so titles
-- follow them across devices. Paste into Supabase > SQL Editor > New query, then Run.
-- Needs protection-setup.sql to have been run first (_rate_check, _clean_label).

create table if not exists public.player_decades (
  name_key   text not null,
  city_key   text not null,
  decade     text not null check (decade in ('60s','70s','80s','90s','00s')),
  played     int  not null default 0 check (played >= 0),
  correct    int  not null default 0 check (correct >= 0),
  updated_at timestamptz not null default now(),
  primary key (name_key, city_key, decade)
);

-- Anyone with the app can read decade progress, but nobody can edit rows directly.
alter table public.player_decades enable row level security;
drop policy if exists "Anyone can read decade progress" on public.player_decades;
create policy "Anyone can read decade progress" on public.player_decades for select using (true);
grant select on public.player_decades to anon, authenticated;

-- Adds one finished game's per-decade results, e.g. {"90s":{"played":10,"correct":7}}.
create or replace function public.record_decades(p_name text, p_city text, p_decades json)
returns json
language plpgsql security definer set search_path = public as $$
declare
  v_name text := lower(trim(p_name));
  v_city text := lower(trim(p_city));
  v_key  text;
  v_val  json;
  v_p    int;
  v_c    int;
  v_tot  int := 0;
  v_out  json;
begin
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  if p_decades is null or json_typeof(p_decades) <> 'object' then
    raise exception 'invalid decades';
  end if;
  for v_key, v_val in select key, value from json_each(p_decades) loop
    if v_key not in ('60s','70s','80s','90s','00s') then raise exception 'invalid decades'; end if;
    v_p := coalesce((v_val->>'played')::int, 0);
    v_c := coalesce((v_val->>'correct')::int, 0);
    if v_p < 0 or v_c < 0 or v_c > v_p then raise exception 'invalid decades'; end if;
    v_tot := v_tot + v_p;
  end loop;
  if v_tot < 1 or v_tot > 20 then raise exception 'invalid decades'; end if;

  perform _rate_check('decades', v_name || '|' || v_city, 30, interval '1 hour');
  perform _rate_check('decades', 'all', 500, interval '1 hour');

  for v_key, v_val in select key, value from json_each(p_decades) loop
    insert into player_decades (name_key, city_key, decade, played, correct)
    values (v_name, v_city, v_key, (v_val->>'played')::int, coalesce((v_val->>'correct')::int, 0))
    on conflict (name_key, city_key, decade) do update set
      played     = player_decades.played + excluded.played,
      correct    = player_decades.correct + excluded.correct,
      updated_at = now();
  end loop;

  select json_object_agg(decade, json_build_object('played', played, 'correct', correct)) into v_out
  from player_decades where name_key = v_name and city_key = v_city;
  return v_out;
end $$;

revoke all on function public.record_decades(text, text, json) from public;
grant execute on function public.record_decades(text, text, json) to anon, authenticated;
