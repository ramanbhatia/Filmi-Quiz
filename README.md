# Filmi Flashback

Guess the film, singer or on-screen star from a short clip of a Bollywood song from the Golden Era (1950s–70s), 1980s, 1990s, 2000s or 2010s.

Play: https://ramanbhatia.github.io/Filmi-Quiz/

- Clips are Apple Music's official 30-second previews.
- The shared leaderboard runs on Supabase; `leaderboard-setup.sql` creates its table and scoring function.
- `question-stats-setup.sql` adds per-question tracking (asked / correct / wrong / skipped by song and question type) and a `question_difficulty` report.
- `streaks-setup.sql` adds streaks that carry across games (current and best streak per player).
- `feedback-setup.sql` stores player feedback (private), including song, clip link, question, answer choices and the player's answer when feedback is about a song.
- `decade-titles-setup.sql` keeps each player's songs played and correct answers per decade, so the 1990s titles (Walkman Rookie at 25 correct up to Superstar of the 90s at 400) follow them across devices. The app shows a "New Title Unlocked" card the moment a player reaches each milestone, even mid-game.
- `backfill-90s-titles.sql` (one-time, run after `decade-titles-setup.sql`) credits every song each player played before decade tracking began to the 1990s.
- `decade-2010s-update.sql` lets per-decade progress include the 2010s (run once after `decade-titles-setup.sql`).
- `decade-golden-update.sql` lets per-decade progress include the 1950s, for the Golden Era tape (run once).
- `protection-setup.sql` adds rate limits and name/city rules to all database functions.

Scoring: one point per correct answer. Streaks count correct answers in a row, across games; a wrong answer or skip ends a streak.
