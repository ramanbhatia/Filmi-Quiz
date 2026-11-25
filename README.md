# Filmi Flashback

Guess the film, singer or on-screen star from a short clip of a Bollywood song from the 1990s or 2000s.

Play: https://ramanbhatia.github.io/Filmi-Quiz/

- Clips are Apple Music's official 30-second previews.
- The shared leaderboard runs on Supabase; `leaderboard-setup.sql` creates its table and scoring function.
- `question-stats-setup.sql` adds per-question tracking (asked / correct / wrong / skipped by song and question type) and a `question_difficulty` report.
- `streaks-setup.sql` adds streaks that carry across games (current and best streak per player).
- `feedback-setup.sql` stores player feedback (private), including song, clip link, question, answer choices and the player's answer when feedback is about a song.

Scoring: one point per correct answer. Streaks count correct answers in a row, across games; a wrong answer or skip ends a streak.
