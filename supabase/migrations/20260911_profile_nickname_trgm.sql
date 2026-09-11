-- =============================================================================
-- Migration: trigram index on profile.nickname (#92)
-- Date: 2026-09-11
-- =============================================================================
-- ADDITIVE. Safe to apply before or after the matching deploy — nothing reads
-- the index directly, and the client change works with or without it.
--
-- The admin pickers in PartyForm and VenueForm fetched EVERY row of `profile`
-- with no limit, purely to power a client-side substring autocomplete. Between
-- them they mount on four pages (parties/create, parties/[id]/edit,
-- venues/create, venues/[id]/edit), so every visit shipped the whole user table
-- to the browser.
--
-- The client half moves that filtering server-side with `.ilike` + `.limit(20)`.
-- That alone bounds what crosses the wire — but NOT what Postgres does: a
-- leading-wildcard `%term%` against an unindexed column is a sequential scan on
-- every keystroke, and `profile` had no index on `nickname` at all (only the two
-- redundant unique indexes on `id`).
--
-- So the limit fixes the payload and this fixes the scan. pg_trgm is already
-- installed and already backs the song search — same treatment, same reason.
-- Compare idx_song_title_trgm / idx_song_artist_trgm, added for #26/#82.
--
-- At 21 profiles none of this is measurable today, which is exactly why #92 was
-- filed rather than fixed at the time: the failure mode is quiet and linear, and
-- the form just gets slower to become usable with no error to notice.
-- =============================================================================

begin;

create index if not exists idx_profile_nickname_trgm
  on public.profile using gin (nickname gin_trgm_ops);

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration needed —
-- an index changes no column, table or function signature.
-- =============================================================================
