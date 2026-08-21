-- =============================================================================
-- Migration: resolve the two deny-all tables (#14)
-- Date: 2026-08-20
-- =============================================================================
-- role: a benign permission lookup (1=admin, 2=venue_owner, 3=user). It was
--   deny-all (RLS on, no policy). Make it readable like the other lookup tables
--   (venue_type, instrument). profile.role ids are already public.
-- temp_spotify_songs: a leftover Spotify import (deny-all, unused, no FKs). It
--   overlaps `song` almost entirely, but 6 rows exist ONLY here — so copy those
--   into `song` first (lossless), then drop the staging table.
-- =============================================================================

begin;

-- 1. role becomes a readable lookup
create policy "Enable read access for all users" on public.role
  for select to anon, authenticated using (true);

-- 2. Preserve the songs that live only in temp_spotify_songs (matched by the
--    Spotify ref_link, which is unique in `song`). Currently 6 rows.
insert into public.song (title, artist, duration, ref_link)
select t.title, t.artist, t.duration, t.ref_link
from public.temp_spotify_songs t
where t.ref_link is not null
  and not exists (select 1 from public.song s where s.ref_link = t.ref_link);

-- 3. Drop the staging table (now fully covered by `song`)
drop table if exists public.temp_spotify_songs;

commit;
