-- Filmi Flashback: abuse protection
-- Paste all of this into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once. Keeps all existing players, stats and feedback.
--
-- Adds:
--   1. Rate limits on saving games, answers and feedback
--   2. Name and city rules (no digits, symbols or links; blocks offensive words)
-- Existing leaderboard rows are not changed; to remove a bad one, delete it
-- in Table Editor > players.

-- ---------- rate limiting ----------
create table if not exists public.api_events (
  id   bigint generated always as identity primary key,
  at   timestamptz not null default now(),
  kind text not null,
  key  text not null
);
create index if not exists api_events_lookup on public.api_events (kind, key, at);
alter table public.api_events enable row level security;   -- no policies: app can't read or write it

create or replace function public._rate_check(p_kind text, p_key text, p_max int, p_window interval)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  select count(*) into n from api_events
   where kind = p_kind and key = p_key and at > now() - p_window;
  if n >= p_max then
    raise exception 'rate limit';
  end if;
  insert into api_events (kind, key) values (p_kind, p_key);
  if random() < 0.02 then
    delete from api_events where at < now() - interval '2 days';   -- housekeeping
  end if;
end $$;
revoke all on function public._rate_check(text, text, int, interval) from public, anon, authenticated;

-- ---------- name and city rules ----------
create or replace function public._clean_label(p text, p_max int)
returns boolean language sql immutable as $$
  select char_length(trim(coalesce(p, ''))) between 1 and p_max
     and trim(p) !~ '[0-9<>{}()@#$%^&*_+=|\\/:;"?!~`\[\]]'
     and lower(p) !~ '(https?|www\.|\.com)'
     and lower(p) !~ '(fuck|chutiya|chutia|bhenchod|behenchod|madarchod|maderchod|bhosd)'
     and lower(p) !~ '\m(shit|shits|cunt|bitch|asshole|bastard|dick|pussy|slut|whore|fag|gandu|nigg[a-z]*)\M';
$$;
revoke all on function public._clean_label(text, int) from public, anon, authenticated;

-- ---------- saving a finished game (current version) ----------
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
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  if p_played < 1 or p_played > 20
     or p_correct < 0 or p_correct > p_played
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

-- ---------- older save function (kept for old copies of the app) ----------
create or replace function public.record_game(
  p_name text, p_city text, p_played int, p_correct int, p_score int
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not _clean_label(p_name, 30) or not _clean_label(p_city, 40) then
    raise exception 'invalid name';
  end if;
  if p_played < 1 or p_played > 20 or p_correct < 0 or p_correct > p_played
     or p_score < 0 or p_score > 1000 then
    raise exception 'invalid game result';
  end if;
  perform _rate_check('game', lower(trim(p_name)) || '|' || lower(trim(p_city)), 30, interval '1 hour');
  perform _rate_check('game', 'all', 500, interval '1 hour');
  insert into players (name, city, songs_played, songs_correct, games, best_score)
  values (trim(p_name), trim(p_city), p_played, p_correct, 1, p_score)
  on conflict (name_key, city_key) do update set
    songs_played  = players.songs_played + excluded.songs_played,
    songs_correct = players.songs_correct + excluded.songs_correct,
    games         = players.games + 1,
    best_score    = greatest(players.best_score, excluded.best_score),
    updated_at    = now();
end $$;

-- ---------- per-question stats ----------
create or replace function public.record_answer(
  p_title text, p_film text, p_kind text, p_result text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_kind not in ('film', 'singer', 'actor') or p_result not in ('correct', 'wrong', 'skipped')
     or char_length(coalesce(p_title, '')) not between 1 and 80
     or char_length(coalesce(p_film, '')) not between 1 and 80 then
    raise exception 'invalid answer';
  end if;
  perform _rate_check('answer', 'all', 300, interval '1 minute');
  perform _rate_check('answer', 'all-hour', 5000, interval '1 hour');
  insert into question_stats (title, film, kind, asked, correct, wrong, skipped)
  values (p_title, p_film, p_kind, 1,
          (p_result = 'correct')::int, (p_result = 'wrong')::int, (p_result = 'skipped')::int)
  on conflict (title, film, kind) do update set
    asked      = question_stats.asked + 1,
    correct    = question_stats.correct + excluded.correct,
    wrong      = question_stats.wrong + excluded.wrong,
    skipped    = question_stats.skipped + excluded.skipped,
    updated_at = now();
end $$;

-- ---------- feedback ----------
create or replace function public.submit_feedback(
  p_screen text, p_message text, p_player_name text, p_player_city text,
  p_song_title text, p_film text, p_track_id bigint, p_clip_url text,
  p_question text, p_options text[], p_user_answer text, p_correct_answer text
) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_screen not in ('signup', 'setup', 'game', 'results')
     or char_length(trim(coalesce(p_message, ''))) not between 1 and 2000
     or char_length(coalesce(p_player_name, '')) > 30
     or char_length(coalesce(p_player_city, '')) > 40
     or char_length(coalesce(p_song_title, '')) > 120
     or char_length(coalesce(p_film, '')) > 120
     or char_length(coalesce(p_question, '')) > 200
     or char_length(coalesce(p_user_answer, '')) > 120
     or char_length(coalesce(p_correct_answer, '')) > 120
     or coalesce(array_length(p_options, 1), 0) > 6
     or (p_clip_url is not null and (char_length(p_clip_url) > 500 or p_clip_url !~ '^https://')) then
    raise exception 'invalid feedback';
  end if;
  perform _rate_check('feedback', coalesce(lower(trim(p_player_name)) || '|' || lower(trim(p_player_city)), 'anonymous'), 10, interval '1 hour');
  perform _rate_check('feedback', 'all', 100, interval '1 hour');
  insert into feedback (screen, message, player_name, player_city, song_title, film, track_id,
                        clip_url, question, options, user_answer, correct_answer)
  values (p_screen, trim(p_message), nullif(trim(p_player_name), ''), nullif(trim(p_player_city), ''),
          p_song_title, p_film, p_track_id, p_clip_url, p_question, p_options, p_user_answer, p_correct_answer);
end $$;

-- Re-assert who may call what (unchanged from before).
revoke all on function public.record_game_v2(text, text, int, int, int, int, int) from public;
grant execute on function public.record_game_v2(text, text, int, int, int, int, int) to anon, authenticated;
revoke all on function public.record_game(text, text, int, int, int) from public;
grant execute on function public.record_game(text, text, int, int, int) to anon, authenticated;
revoke all on function public.record_answer(text, text, text, text) from public;
grant execute on function public.record_answer(text, text, text, text) to anon, authenticated;
revoke all on function public.submit_feedback(text, text, text, text, text, text, bigint, text, text, text[], text, text) from public;
grant execute on function public.submit_feedback(text, text, text, text, text, text, bigint, text, text, text[], text, text) to anon, authenticated;
