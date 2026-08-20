-- =============================================================================
-- Migration: resolve the two deny-all tables (#14)
-- Date: 2026-08-20
-- =============================================================================
-- role: a benign permission lookup (1=admin, 2=venue_owner, 3=user). It was
--   deny-all (RLS on, no policy) which is why nothing could read role names.
--   Make it readable like the other lookup tables (venue_type, instrument).
--   profile.role ids are already public, so this exposes nothing new.
-- temp_spotify_songs: a leftover Spotify import (deny-all, unused by the app, no
--   foreign keys). Dropping it removes ~6,500 cruft rows.
--
-- NOTE: the DROP TABLE is IRREVERSIBLE. If you'd rather keep that data for now,
-- run only the CREATE POLICY statement and skip the DROP.
-- =============================================================================

begin;

create policy "Enable read access for all users" on public.role
  for select to anon, authenticated using (true);

drop table if exists public.temp_spotify_songs;

commit;
