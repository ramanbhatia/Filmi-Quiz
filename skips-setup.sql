-- Filmi Flashback: count skipped questions per player.
-- Paste into Supabase > SQL Editor > New query, then Run. Safe to run more than once.
-- Skips are counted from the day this runs; earlier skipped questions can't be recovered
-- (they were only logged anonymously), so they remain counted as answered.

alter table public.players
  add column if not exists songs_skipped int not null default 0;

-- Same as record_game_v2, plus the number of questions skipped in the game.
create or replace function public.record_game_v3(
  p_name text, p_city text, p_played int, p_correct int,
  p_lead int, p_tail int, p_max_run int, p_skipped int
) returns json
language plpgsql security definer set search_path = public as $$
declare
  v_cur  int := 0;
  v_best int := 0;
  v_new  int;
  v_top  int;
begin
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  if p_played < 1 or p_played > 20
     or p_correct < 0 or p_correct > p_played
     or p_skipped is null or p_skipped < 0 or p_skipped > p_played - p_correct
     or p_lead < 0 or p_tail < 0 or p_max_run < 0
     or p_max_run > p_correct or p_lead > p_max_run or p_tail > p_max_run
     or (p_correct = p_played and (p_lead <> p_played or p_tail <> p_played or p_max_run <> p_played))
     or (p_lead = p_played and p_correct <> p_played) then
    raise exception 'invalid game result';
  end if;
  perform _rate_check('game', lower(trim(p_name)) || '|' || lower(trim(p_city)), 30, interval '1 hour');
  perform _rate_check('game', 'all', 500, interval '1 hour');

  select pl.current_streak, pl.best_streak into v_cur, v_best
  from players pl
  where pl.name_key = lower(trim(p_name)) and pl.city_key = lower(trim(p_city))
  for update;
  v_cur  := coalesce(v_cur, 0);
  v_best := coalesce(v_best, 0);

  if p_lead = p_played then
    v_new := v_cur + p_played;
  else
    v_new := p_tail;
  end if;
  v_top := greatest(v_best, v_cur + p_lead, p_max_run, v_new);

  insert into players (name, city, songs_played, songs_correct, songs_skipped, games, best_score, current_streak, best_streak)
  values (trim(p_name), trim(p_city), p_played, p_correct, p_skipped, 1, p_correct, v_new, v_top)
  on conflict (name_key, city_key) do update set
    songs_played   = players.songs_played + excluded.songs_played,
    songs_correct  = players.songs_correct + excluded.songs_correct,
    songs_skipped  = players.songs_skipped + excluded.songs_skipped,
    games          = players.games + 1,
    best_score     = greatest(players.best_score, excluded.best_score),
    current_streak = v_new,
    best_streak    = v_top,
    updated_at     = now();

  return json_build_object('current_streak', v_new, 'best_streak', v_top);
end $$;

revoke all on function public.record_game_v3(text, text, int, int, int, int, int, int) from public;
grant execute on function public.record_game_v3(text, text, int, int, int, int, int, int) to anon, authenticated;
