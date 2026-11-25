-- Nineties Filmi Quiz: per-question difficulty tracking
-- Paste all of this into Supabase > SQL Editor > New query, then click Run.
-- Safe to run more than once. Does not touch the leaderboard (players table).

create table if not exists public.question_stats (
  title       text not null check (char_length(title) between 1 and 80),
  film        text not null check (char_length(film) between 1 and 80),
  kind        text not null check (kind in ('film', 'singer', 'actor')),
  asked       int  not null default 0,   -- times the question was shown
  correct     int  not null default 0,   -- answered correctly
  wrong       int  not null default 0,   -- answered incorrectly
  skipped     int  not null default 0,   -- skipped without answering
  updated_at  timestamptz not null default now(),
  primary key (title, film, kind)
);

alter table public.question_stats enable row level security;
drop policy if exists "Anyone can read question stats" on public.question_stats;
create policy "Anyone can read question stats" on public.question_stats for select using (true);
grant select on public.question_stats to anon, authenticated;

-- The only way to add data: one call per answered or skipped question.
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

revoke all on function public.record_answer(text, text, text, text) from public;
grant execute on function public.record_answer(text, text, text, text) to anon, authenticated;

-- Ready-made difficulty report. In Supabase: Table Editor > question_difficulty,
-- or SQL Editor: select * from question_difficulty;
create or replace view public.question_difficulty
with (security_invoker = true) as
select
  title, film, kind, asked, correct, wrong, skipped,
  round(100.0 * correct / nullif(asked, 0), 1) as correct_pct,
  case
    when asked < 5 then 'not enough data'
    when correct::numeric / asked >= 0.75 then 'easy'
    when correct::numeric / asked >= 0.40 then 'medium'
    else 'hard'
  end as difficulty,
  updated_at
from public.question_stats
order by correct_pct asc nulls last, asked desc;

grant select on public.question_difficulty to anon, authenticated;
