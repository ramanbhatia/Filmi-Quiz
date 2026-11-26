-- Filmi Flashback: one-time backfill of 1990s title progress (option A)
-- Credits every song each player has played and answered correctly so far to the 1990s.
-- Run decade-titles-setup.sql first. Safe to run more than once: it sets the 1990s
-- totals rather than adding to them, and it never lowers a count.

insert into public.player_decades (name_key, city_key, decade, played, correct)
select p.name_key, p.city_key, '90s',
       greatest(p.songs_played  - coalesce(o.played, 0), 0),
       greatest(p.songs_correct - coalesce(o.correct, 0), 0)
from public.players p
left join (
  select name_key, city_key, sum(played) as played, sum(correct) as correct
  from public.player_decades
  where decade <> '90s'
  group by name_key, city_key
) o on o.name_key = p.name_key and o.city_key = p.city_key
where p.songs_played > 0
on conflict (name_key, city_key, decade) do update set
  played     = greatest(player_decades.played,  excluded.played),
  correct    = greatest(player_decades.correct, excluded.correct),
  updated_at = now();

-- Check the result:
select name_key, city_key, decade, played, correct
from public.player_decades
order by correct desc;
