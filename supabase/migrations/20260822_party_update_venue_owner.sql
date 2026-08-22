-- =============================================================================
-- Migration: party UPDATE must also allow the venue OWNER (#31 follow-up)
-- Date: 2026-08-22
-- =============================================================================
-- 20260822_venue_approval.sql added venue_admin *table* members to the party
-- UPDATE policy, but NOT the venue's owner (venue.created_by). Venue creators are
-- not auto-added to venue_admin, so a venue owner could not approve/decline/cancel
-- a toque at their own venue — the UPDATE silently matched 0 rows while the UI
-- optimistically showed success. Add the owner clause to match the venue's own
-- UPDATE policy and the app's isVenueAdmin (owner OR admin).
-- =============================================================================

begin;

drop policy "allow update to party admins" on public.party;

create policy "allow update to party admins" on public.party
  for update to authenticated using (
    (created_by = (select auth.uid()))
    or exists (
      select 1 from public.party_admin
      where party_admin.party_id = party.id and party_admin.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.venue v
      where v.id = party.venue and v.created_by = (select auth.uid())
    )
    or exists (
      select 1 from public.venue_admin
      where venue_admin.venue_id = party.venue and venue_admin.user_id = (select auth.uid())
    )
  ) with check (true);

commit;
