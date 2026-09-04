-- =============================================================================
-- Migration: a suggester may delete their own suggested song (#77)
-- Date: 2026-09-04
-- =============================================================================
-- The multi-add setlist flow commits each song on tap, so "remove" is a real
-- delete. The performance DELETE policy was party-admins-only, but a band manager
-- adding their setlist to a toque they don't own is a non-admin — they could add
-- but not un-add. Relax it: the song's suggester may delete their own suggestion
-- (bounded — only your own; deleting cascades performance_user). Party
-- admins keep their existing remove-from-setlist power (#62).
-- =============================================================================

begin;

drop policy if exists "delete performance: party admins" on public.performance;
create policy "delete performance: admins or suggester" on public.performance
  for delete to authenticated using (
    performance.suggested_by = (select auth.uid())
    or exists (
      select 1 from public.party p
      where p.id = performance.party
        and (
          p.created_by = (select auth.uid())
          or exists (select 1 from public.party_admin pa where pa.party_id = p.id and pa.user_id = (select auth.uid()))
        )
    )
  );

commit;
