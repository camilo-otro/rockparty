-- =============================================================================
-- Migration: tighten UPDATE RLS on performance & performance_user
-- Date: 2026-08-11
-- =============================================================================
-- Before: both tables' UPDATE policies used `using (true)`, so ANY authenticated
-- user could reorder/edit any party's set list and rewrite any performer's
-- instrument sign-up. The reorder UI already gates to the party owner
-- (parties/[id]/+page.svelte), but that gate is client-side only.
--
-- After (option 1 — owner + party admins, matching the party UPDATE policy):
--   * performance UPDATE      -> only if you own or admin the parent party
--   * performance_user UPDATE -> only your own row (mirrors its DELETE policy)
--
-- Note: for UPDATE policies, omitting WITH CHECK makes Postgres reuse the USING
-- expression as the check on the new row, which is what we want here.
-- =============================================================================

-- performance: restrict UPDATE to the parent party's owner or admins ----------
drop policy if exists "Enable Update for authenticated users only" on public.performance;

create policy "Enable Update for authenticated users only" on public.performance
  for update to authenticated
  using (
    exists (
      select 1 from public.party p
      where p.id = performance.party
        and (
          p.created_by = auth.uid()
          or exists (
            select 1 from public.party_admin pa
            where pa.party_id = p.id and pa.user_id = auth.uid()
          )
        )
    )
  );

-- performance_user: restrict UPDATE to the owning user ------------------------
drop policy if exists "Enable update for authenticated users only" on public.performance_user;

create policy "Enable update for authenticated users only" on public.performance_user
  for update to authenticated
  using (user_id = auth.uid());
