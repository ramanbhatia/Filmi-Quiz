-- Nineties Filmi Quiz: shared leaderboard
-- Paste all of this into Supabase > SQL Editor > New query, then click Run.

create table if not exists public.players (
  id            bigint generated always as identity primary key,
  name          text not null check (char_length(trim(name)) between 1 and 30),
  city          text not null check (char_length(trim(city)) between 1 and 40),
  name_key      text generated always as (lower(trim(name))) stored,
  city_key      text generated always as (lower(trim(city))) stored,
  songs_played  int  not null default 0,
  songs_correct int  not null default 0,
  games         int  not null default 0,
  best_score    int  not null default 0,
  updated_at    timestamptz not null default now(),
  unique (name_key, city_key)
);

-- Anyone with the app can read the leaderboard, but nobody can edit rows directly.
alter table public.players enable row level security;
drop policy if exists "Anyone can read the leaderboard" on public.players;
create policy "Anyone can read the leaderboard" on public.players for select using (true);
grant select on public.players to anon, authenticated;

-- The only way to add scores: one call per finished game, with basic sanity checks.
create or replace function public.record_game(
  p_name text, p_city text, p_played int, p_correct int, p_score int
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_played < 1 or p_played > 20 or p_correct < 0 or p_correct > p_played
     or p_score < 0 or p_score > 1000 then
    raise exception 'invalid game result';
  end if;
  insert into players (name, city, songs_played, songs_correct, games, best_score)
  values (trim(p_name), trim(p_city), p_played, p_correct, 1, p_score)
  on conflict (name_key, city_key) do update set
    songs_played  = players.songs_played + excluded.songs_played,
    songs_correct = players.songs_correct + excluded.songs_correct,
    games         = players.games + 1,
    best_score    = greatest(players.best_score, excluded.best_score),
    updated_at    = now();
end $$;

revoke all on function public.record_game(text, text, int, int, int) from public;
grant execute on function public.record_game(text, text, int, int, int) to anon, authenticated;
