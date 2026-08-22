-- =============================================================================
-- Migration: venue approval flow — let venue admins update their parties (#31)
-- Date: 2026-08-22
-- =============================================================================
-- Venue admins need to approve/decline a `pending_venue` toque at their venue
-- (pending_venue → confirmed / cancelled). The party UPDATE policy today only
-- allows the creator or party admins, so add the venue's creator/admins.
-- (SELECT already lets venue admins see the party — see the party SELECT policy.)
--
-- Note: this grants venue admins UPDATE on the whole party row, not just status
-- — acceptable for trusted venue admins in this MVP; the UI only exposes
-- approve/decline/cancel to them.
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
      select 1 from public.venue_admin
      where venue_admin.venue_id = party.venue and venue_admin.user_id = (select auth.uid())
    )
  ) with check (true);

commit;
