-- =============================================================================
-- Migration: optional free-text reason on cancel/decline (#31 usability)
-- Date: 2026-08-22
-- =============================================================================
-- When a venue declines a toque, the owner can leave a short reason the
-- organizer sees. `cancel_reason` stays the coded reason ('venue_declined' /
-- 'organizer'); `cancel_note` holds the optional human explanation.
-- =============================================================================

begin;

alter table public.party
  add column if not exists cancel_note text;

commit;
