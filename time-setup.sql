-- Filmi Flashback: track time spent playing.
-- Paste into Supabase > SQL Editor > New query, then Run. Safe to run more than once.
-- Needs skips-setup.sql to have been run first. Times are counted from the day this runs.
--   play_seconds  : total active play time (pauses while the app is in the background or a title card is showing)
--   answer_ms     : total time from a song starting to the player tapping an answer (skips not included)
--   answers_timed : how many answers answer_ms covers
--   games_timed   : how many games play_seconds covers (older games had no timer)

alter table public.players
  add column if not exists play_seconds  bigint not null default 0,
  add column if not exists answer_ms     bigint not null default 0,
  add column if not exists answers_timed int    not null default 0,
  add column if not exists games_timed   int    not null default 0;

create or replace function public.record_game_v4(
  p_name text, p_city text, p_played int, p_correct int,
  p_lead int, p_tail int, p_max_run int, p_skipped int,
  p_seconds int, p_answer_ms bigint, p_answers_timed int
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
     or p_seconds is null or p_seconds < 0 or p_seconds > least(7200, p_played * 600)
     or p_answers_timed is null or p_answers_timed < 0 or p_answers_timed > p_played - p_skipped
     or p_answer_ms is null or p_answer_ms < 0 or p_answer_ms > p_answers_timed * 120000::bigint
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

  insert into players (name, city, songs_played, songs_correct, songs_skipped, play_seconds, answer_ms, answers_timed, games_timed,
                       games, best_score, current_streak, best_streak)
  values (trim(p_name), trim(p_city), p_played, p_correct, p_skipped, p_seconds, p_answer_ms, p_answers_timed, 1,
          1, p_correct, v_new, v_top)
  on conflict (name_key, city_key) do update set
    songs_played   = players.songs_played + excluded.songs_played,
    songs_correct  = players.songs_correct + excluded.songs_correct,
    songs_skipped  = players.songs_skipped + excluded.songs_skipped,
    play_seconds   = players.play_seconds + excluded.play_seconds,
    answer_ms      = players.answer_ms + excluded.answer_ms,
    answers_timed  = players.answers_timed + excluded.answers_timed,
    games_timed    = players.games_timed + 1,
    games          = players.games + 1,
    best_score     = greatest(players.best_score, excluded.best_score),
    current_streak = v_new,
    best_streak    = v_top,
    updated_at     = now();

  return json_build_object('current_streak', v_new, 'best_streak', v_top);
end $$;

revoke all on function public.record_game_v4(text, text, int, int, int, int, int, int, int, bigint, int) from public;
grant execute on function public.record_game_v4(text, text, int, int, int, int, int, int, int, bigint, int) to anon, authenticated;
