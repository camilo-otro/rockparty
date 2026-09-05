-- =============================================================================
-- Migration: backfill duration for user-added songs (data fix)
-- Date: 2026-09-04
-- =============================================================================
-- song.duration is decimal MINUTES. Songs added through the add-song flow before
-- it stored duration fell back to the column default (3), which skewed the band
-- set-length estimates. Values below are the real Spotify durations, fetched via
-- the spotify-track Edge Function from each song's own ref_link.
--
-- NOT included: ~27 older catalog songs also sitting at 3. Those are correct —
-- Spotify really reports 180s for their linked tracks (verified), the value just
-- coincides with the default. The add-song flow now stores duration, so this is
-- a one-off.
-- =============================================================================

begin;

update public.song as s
set duration = v.minutes
from (values
  (7032, 4.95),  -- Fiesta Pagana — Mägo de Oz          (4:57)
  (7033, 2.23),  -- She — Green Day                      (2:14)
  (7040, 3.57),  -- Never Gonna Give You Up — Rick Astley(3:34)
  (7041, 7.43),  -- One — Metallica                      (7:26)
  (7042, 3.80),  -- Pride (In The Name Of Love) — U2     (3:48)
  (7043, 2.92),  -- Shy Away — Twenty One Pilots         (2:55)
  (7044, 5.07)   -- Un Millón De Años Luz — Soda Stereo  (5:04)
) as v(id, minutes)
where s.id = v.id
  and s.duration = 3;  -- only touch rows still at the default

commit;
