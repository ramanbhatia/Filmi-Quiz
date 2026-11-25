-- Nineties Filmi Quiz: player feedback
-- Paste all of this into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once. Does not touch players or question stats.
-- Feedback is private: players can send it but cannot read it.
-- You can read it in Supabase > Table Editor > feedback.

create table if not exists public.feedback (
  id              bigint generated always as identity primary key,
  created_at      timestamptz not null default now(),
  screen          text not null,          -- signup, setup, game, results
  message         text not null,
  player_name     text,
  player_city     text,
  -- filled in only when the feedback is about a specific song
  song_title      text,
  film            text,
  track_id        bigint,                 -- Apple Music track id
  clip_url        text,                   -- link to the audio clip that was played
  question        text,                   -- e.g. "Who sings on this track?"
  options         text[],                 -- the four answer choices shown
  user_answer     text,                   -- what the player picked, "Skipped", or null if not answered yet
  correct_answer  text
);

alter table public.feedback enable row level security;
-- No select policy on purpose: the app can't read feedback back.

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
  insert into feedback (screen, message, player_name, player_city, song_title, film, track_id,
                        clip_url, question, options, user_answer, correct_answer)
  values (p_screen, trim(p_message), nullif(trim(p_player_name), ''), nullif(trim(p_player_city), ''),
          p_song_title, p_film, p_track_id, p_clip_url, p_question, p_options, p_user_answer, p_correct_answer);
end $$;

revoke all on function public.submit_feedback(text, text, text, text, text, text, bigint, text, text, text[], text, text) from public;
grant execute on function public.submit_feedback(text, text, text, text, text, text, bigint, text, text, text[], text, text) to anon, authenticated;
