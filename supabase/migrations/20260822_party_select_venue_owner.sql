-- =============================================================================
-- Migration: party SELECT must also allow the venue OWNER (#31 follow-up)
-- Date: 2026-08-22
-- =============================================================================
-- Same gap as the UPDATE policy: the party SELECT policy checked the venue_admin
-- TABLE but not the venue's owner (venue.created_by). Venue creators aren't in
-- venue_admin, so a venue owner could not see a NON-public toque (draft/pending/
-- cancelled) created by someone else at their venue — the "POR APROBAR" queue
-- was empty for them, and approve/decline's UPDATE ... RETURNING failed because
-- the (now non-public) row couldn't be read back.
--
-- can_see_party() is SECURITY INVOKER (a plain existence check under the caller's
-- RLS), so fixing this SELECT policy also lets venue owners see the setlists of
-- non-public toques at their venue.
-- =============================================================================

begin;

drop policy "select party: public statuses or owner/admins" on public.party;

create policy "select party: public statuses or owner/admins" on public.party
  for select to anon, authenticated
  using (
    status in ('confirmed', 'live', 'completed')
    or created_by = (select auth.uid())
    or exists (
      select 1 from public.party_admin pa
      where pa.party_id = party.id and pa.user_id = (select auth.uid())
    )
    or exists (
      select 1 from public.venue v
      where v.id = party.venue and v.created_by = (select auth.uid())
    )
    or exists (
      select 1 from public.venue_admin va
      where va.venue_id = party.venue and va.user_id = (select auth.uid())
    )
  );

commit;
