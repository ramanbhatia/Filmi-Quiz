-- Filmi Flashback: leaderboard with per-era stats and titles.
-- Paste into Supabase > SQL Editor > New query, then Run. Read-only.
-- Needs skips-setup.sql to have been run first (adds the songs_skipped column).
-- Skips are only counted from the day skips-setup.sql was run; earlier skips show as answered.
-- Era columns show "correct/played (pct%)". The Golden Era combines the 1950s, 60s and 70s.

with ladder(era, need, title) as (
  values
  ('gold', 25,'Transistor Tuner'),('gold', 50,'Black & White Buff'),('gold', 75,'Binaca Geetmala Regular'),('gold',100,'Gramophone Guru'),
  ('gold',125,'Kashmir Romantic'),('gold',150,'Cabaret Connoisseur'),('gold',200,'Matinee Idol'),('gold',400,'Sartaj of the Golden Era'),
  ('80s', 25,'Antenna Adjuster'),('80s', 50,'Chitrahaar Regular'),('80s', 75,'Video Parlour Patron'),('80s',100,'Gold Chain Groover'),
  ('80s',125,'Disco Dancer'),('80s',150,'Mogambo Khush Hua!'),('80s',200,'Ek Do Teen Showstopper'),('80s',400,'Legend of the Disco Era'),
  ('90s', 25,'Walkman Rookie'),('90s', 50,'T-Series Collector'),('90s', 75,'Mixtape Maker'),('90s',100,'Antakshari Ace'),
  ('90s',125,'Cable TV Connoisseur'),('90s',150,'Silver Jubilee Star'),('90s',200,'Golden Jubilee Star'),('90s',400,'Superstar of the 90s'),
  ('00s', 25,'Ringtone Rookie'),('00s', 50,'FM Request Regular'),('00s', 75,'Remix Raver'),('00s',100,'Multiplex Maven'),
  ('00s',125,'Goa Road Tripper'),('00s',150,'Item Song Icon'),('00s',200,'100 Crore Club Member'),('00s',400,'Legend of the Multiplex Era')
),
eras as (   -- roll decades up into the game's eras
  select name_key, city_key,
         case when decade in ('50s','60s','70s') then 'gold' else decade end as era,
         sum(played) as played, sum(correct) as correct
  from public.player_decades
  group by 1, 2, 3
),
titled as (  -- highest title reached in each era (null if none yet; the 2010s have no titles)
  select e.*,
         (select l.title from ladder l where l.era = e.era and l.need <= e.correct order by l.need desc limit 1) as title
  from eras e
),
fmt as (
  select name_key, city_key, era, title,
         correct || '/' || played || ' (' || round(100.0 * correct / nullif(played, 0)) || '%)' as stat
  from titled
)
select
  row_number() over (order by p.songs_correct desc, p.songs_played asc, p.name) as rank,
  p.name,
  p.city,
  p.games                              as games_played,
  p.songs_played                       as questions_seen,
  p.songs_played - p.songs_skipped     as questions_answered,
  p.songs_skipped                      as questions_skipped,
  p.songs_correct || '/' || p.songs_played
    || ' (' || coalesce(round(100.0 * p.songs_correct / nullif(p.songs_played, 0)) || '%', '—') || ')' as overall,
  p.best_streak,
  max(f.stat)  filter (where f.era = 'gold') as golden_era,
  max(f.title) filter (where f.era = 'gold') as golden_era_title,
  max(f.stat)  filter (where f.era = '80s')  as era_80s,
  max(f.title) filter (where f.era = '80s')  as title_80s,
  max(f.stat)  filter (where f.era = '90s')  as era_90s,
  max(f.title) filter (where f.era = '90s')  as title_90s,
  max(f.stat)  filter (where f.era = '00s')  as era_2000s,
  max(f.title) filter (where f.era = '00s')  as title_2000s,
  max(f.stat)  filter (where f.era = '10s')  as era_2010s
from public.players p
left join fmt f on f.name_key = p.name_key and f.city_key = p.city_key
group by p.name, p.city, p.games, p.songs_correct, p.songs_played, p.songs_skipped, p.best_streak
order by rank;
