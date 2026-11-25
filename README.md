# Nineties Filmi Quiz

Guess the film, singer or on-screen star from a short clip of a 1990s Bollywood song.

Play: https://ramanbhatia.github.io/Filmi-Quiz/

- Clips are Apple Music's official 30-second previews.
- The shared leaderboard runs on Supabase; `leaderboard-setup.sql` creates its table and scoring function.
- `question-stats-setup.sql` adds per-question tracking (asked / correct / wrong / skipped by song and question type) and a `question_difficulty` report.
