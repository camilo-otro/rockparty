-- =============================================================================
-- Migration: a band-owned song is not an open jam (#74 follow-up, epic #40)
-- Date: 2026-09-03
-- =============================================================================
-- A band OWNS its song; the empty template instruments it doesn't cover are NOT
-- open slots for outsiders (that's the deferred v2 "collabs" guest-slot feature).
-- The setlist row already suppresses the gaps UI, but the performance detail page
-- still let anyone self-sign-up to a band song's uncovered instruments. RLS is the
-- real boundary, so close it there:
--
--   INSERT: no direct client signup to a band-owned performance — its lineup
--           comes only from sign_band_up (SECURITY DEFINER, bypasses RLS).
--   UPDATE/DELETE: band-tagged rows are managed as a unit by the definer RPCs
--           (set_band_signup_status) and FK cascades, never edited row-by-row.
--
-- Non-band signups (open jams) are completely unaffected.
-- =============================================================================

begin;

drop policy if exists "signup insert: self, admin, or proponent" on public.performance_user;
create policy "signup insert: self, admin, or proponent" on public.performance_user
  for insert to authenticated with check (
    (select perf.band_id from public.performance perf where perf.id = performance_user.performance_id) is null
    and (
      user_id = (select auth.uid())
      or exists (
        select 1 from public.performance perf join public.party pt on pt.id = perf.party
        where perf.id = performance_user.performance_id and (
          pt.created_by = (select auth.uid())
          or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
          or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
        )
      )
    )
  );

drop policy if exists "signup update: self, admin, or proponent" on public.performance_user;
create policy "signup update: self, admin, or proponent" on public.performance_user
  for update to authenticated using (
    band_id is null
    and (
      user_id = (select auth.uid())
      or exists (
        select 1 from public.performance perf join public.party pt on pt.id = perf.party
        where perf.id = performance_user.performance_id and (
          pt.created_by = (select auth.uid())
          or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
          or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
        )
      )
    )
  );

drop policy if exists "signup delete: self, admin, or proponent" on public.performance_user;
create policy "signup delete: self, admin, or proponent" on public.performance_user
  for delete to authenticated using (
    band_id is null
    and (
      user_id = (select auth.uid())
      or exists (
        select 1 from public.performance perf join public.party pt on pt.id = perf.party
        where perf.id = performance_user.performance_id and (
          pt.created_by = (select auth.uid())
          or exists (select 1 from public.party_admin pa where pa.party_id = pt.id and pa.user_id = (select auth.uid()))
          or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
        )
      )
    )
  );

commit;
