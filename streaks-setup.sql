-- Nineties Filmi Quiz: streaks that carry across games
-- Paste all of this into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once. Existing players and totals are kept.

alter table public.players
  add column if not exists current_streak int not null default 0,
  add column if not exists best_streak    int not null default 0;

-- Called once per finished game. The app sends:
--   p_lead    = correct answers in a row from the start of this game
--   p_tail    = correct answers in a row at the end of this game
--   p_max_run = longest run of correct answers inside this game
-- The database joins them to the player's streak from earlier games.
-- A wrong answer or a skip ends a streak.
create or replace function public.record_game_v2(
  p_name text, p_city text, p_played int, p_correct int,
  p_lead int, p_tail int, p_max_run int
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_cur  int := 0;
  v_best int := 0;
  v_new  int;
  v_top  int;
begin
  if p_played < 1 or p_played > 20
     or p_correct < 0 or p_correct > p_played
     or p_lead < 0 or p_tail < 0 or p_max_run < 0
     or p_max_run > p_correct or p_lead > p_max_run or p_tail > p_max_run
     or (p_correct = p_played and (p_lead <> p_played or p_tail <> p_played or p_max_run <> p_played))
     or (p_lead = p_played and p_correct <> p_played) then
    raise exception 'invalid game result';
  end if;

  select pl.current_streak, pl.best_streak into v_cur, v_best
  from players pl
  where pl.name_key = lower(trim(p_name)) and pl.city_key = lower(trim(p_city))
  for update;
  v_cur  := coalesce(v_cur, 0);
  v_best := coalesce(v_best, 0);

  if p_lead = p_played then
    v_new := v_cur + p_played;          -- perfect game: streak keeps growing
  else
    v_new := p_tail;                    -- streak restarted during this game
  end if;
  v_top := greatest(v_best, v_cur + p_lead, p_max_run, v_new);

  insert into players (name, city, songs_played, songs_correct, games, best_score, current_streak, best_streak)
  values (trim(p_name), trim(p_city), p_played, p_correct, 1, p_correct, v_new, v_top)
  on conflict (name_key, city_key) do update set
    songs_played   = players.songs_played + excluded.songs_played,
    songs_correct  = players.songs_correct + excluded.songs_correct,
    games          = players.games + 1,
    best_score     = greatest(players.best_score, excluded.best_score),
    current_streak = v_new,
    best_streak    = v_top,
    updated_at     = now();

  return json_build_object('current_streak', v_new, 'best_streak', v_top);
end $$;

revoke all on function public.record_game_v2(text, text, int, int, int, int, int) from public;
grant execute on function public.record_game_v2(text, text, int, int, int, int, int) to anon, authenticated;
