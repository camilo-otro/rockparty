-- =============================================================================
-- Migration: allow removing a song from a setlist (#62)
-- Date: 2026-08-24
-- =============================================================================
-- `performance` had RLS enabled with INSERT/SELECT/UPDATE policies but NO DELETE
-- policy, so DELETE was deny-all for everyone — a song could never be removed
-- from a setlist. Add a DELETE policy scoped to the parent party's approvers
-- (creator or party_admin), mirroring the existing UPDATE policy exactly, so the
-- same people who can reorder/edit the setlist can also remove a song.
--
-- performance_user.performance_id FKs to performance ON DELETE CASCADE, so a
-- song's signups are removed with it (the cascade bypasses child RLS).
-- =============================================================================

begin;

create policy "delete performance: party admins" on public.performance
  for delete to authenticated using (
    exists (
      select 1 from public.party p
      where p.id = performance.party
        and (
          p.created_by = (select auth.uid())
          or exists (
            select 1 from public.party_admin pa
            where pa.party_id = p.id and pa.user_id = (select auth.uid())
          )
        )
    )
  );

commit;
