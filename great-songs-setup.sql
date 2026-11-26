-- Filmi Flashback: "My Great Song! List"
-- Keeps the songs each player marks with "Wah! Great Song!", so the list follows them across devices.
-- Paste into Supabase > SQL Editor > New query, then Run.
-- Needs protection-setup.sql to have been run first (_rate_check, _clean_label).

create table if not exists public.player_great_songs (
  name_key  text   not null,
  city_key  text   not null,
  song_id   bigint not null check (song_id > 0),
  title     text   not null check (char_length(title) between 1 and 120),
  film      text   not null check (char_length(film) between 1 and 120),
  year      int    not null check (year between 1930 and 2030),
  added_at  timestamptz not null default now(),
  primary key (name_key, city_key, song_id)
);
create index if not exists player_great_songs_player on public.player_great_songs (name_key, city_key, added_at desc);

-- Anyone with the app can read a list, but nobody can edit rows directly.
alter table public.player_great_songs enable row level security;
drop policy if exists "Anyone can read great songs" on public.player_great_songs;
create policy "Anyone can read great songs" on public.player_great_songs for select using (true);
grant select on public.player_great_songs to anon, authenticated;

-- Adds (p_on = true) or removes (p_on = false) one song from a player's list.
create or replace function public.set_great_song(
  p_name text, p_city text, p_song_id bigint, p_title text, p_film text, p_year int, p_on boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_name text := lower(trim(p_name));
  v_city text := lower(trim(p_city));
begin
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  if p_song_id is null or p_song_id <= 0 then raise exception 'invalid song'; end if;

  perform _rate_check('great_song', v_name || '|' || v_city, 200, interval '1 hour');
  perform _rate_check('great_song', 'all', 3000, interval '1 hour');

  if p_on then
    if coalesce(char_length(trim(p_title)), 0) not between 1 and 120
       or coalesce(char_length(trim(p_film)), 0) not between 1 and 120
       or p_year is null or p_year not between 1930 and 2030 then
      raise exception 'invalid song';
    end if;
    if (select count(*) from player_great_songs where name_key = v_name and city_key = v_city) >= 2000 then
      raise exception 'list full';
    end if;
    insert into player_great_songs (name_key, city_key, song_id, title, film, year)
    values (v_name, v_city, p_song_id, trim(p_title), trim(p_film), p_year)
    on conflict (name_key, city_key, song_id) do nothing;
  else
    delete from player_great_songs where name_key = v_name and city_key = v_city and song_id = p_song_id;
  end if;
end $$;

revoke all on function public.set_great_song(text, text, bigint, text, text, int, boolean) from public;
grant execute on function public.set_great_song(text, text, bigint, text, text, int, boolean) to anon, authenticated;

-- Handy for you: the most-loved songs across all players.
-- select title, film, year, count(*) as players from player_great_songs
-- group by title, film, year order by players desc limit 25;
