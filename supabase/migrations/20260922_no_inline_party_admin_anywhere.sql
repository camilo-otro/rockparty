-- =============================================================================
-- Migration: the last six policies stop inlining party_admin (#113)
-- Date: 2026-09-22
-- =============================================================================
-- BEHAVIOUR-PRESERVING. The same people, evaluated without RLS on party_admin.
-- No client change. Safe to apply at any time.
--
-- -----------------------------------------------------------------------------
-- Why finish this
-- -----------------------------------------------------------------------------
-- CLAUDE.md: "A table referenced inside an RLS policy is read AS THE CALLING
-- USER, so its own policies apply again." Every guard in this schema is a DEFINER
-- helper for that reason. These six predate the rule.
--
-- They are NOT cycles — each reads party_admin from a policy on a different
-- relation, so the chain runs party_admin -> can_see_party -> party -> DEFINER
-- helpers and terminates. That was checked, not assumed.
--
-- They are still worth removing. On 2026-09-18 the same pattern on party_admin's
-- OWN policies took out toque creation for three days, and it was invisible
-- until somebody tried to create one: `party_admin` had had a trivially-true
-- SELECT policy, narrowing it gave that policy a body, and the body closed a
-- loop that had been latent for months. Every one of these six sits one policy
-- change away from the same surprise. The fix is mechanical; the bug is not.
--
-- -----------------------------------------------------------------------------
-- The substitution
-- -----------------------------------------------------------------------------
-- All six contain, verbatim, the definition of is_party_admin:
--
--   pt.created_by = auth.uid()
--   or exists (select 1 from party_admin pa
--              where pa.party_id = pt.id and pa.user_id = auth.uid())
--
-- so each becomes public.is_party_admin(pt.id). Nothing else moves — the
-- proponent branch, the band_id guards and the approved-is-public rule are
-- copied across untouched, so the diff stays auditable against the originals.
--
-- One narrowing that is not a narrowing: the old `exists (select 1 from party p
-- where p.id = ... and <admin test>)` also required the PARTY row to be visible
-- to the caller. is_party_admin reads it with the owner's rights instead. Same
-- answer, because being the creator or an admin already grants visibility
-- through party's own SELECT policy.
-- =============================================================================

begin;

-- 1 --- performance -----------------------------------------------------------
drop policy if exists "delete performance: admins or suggester" on public.performance;
create policy "delete performance: admins or suggester" on public.performance
  for delete to authenticated
  using (
    suggested_by = (select auth.uid())
    or public.is_party_admin(performance.party)
  );

drop policy if exists "Enable Update for authenticated users only" on public.performance;
create policy "update performance: party admins" on public.performance
  for update to authenticated
  using (public.is_party_admin(performance.party));

-- 2 --- performance_user ------------------------------------------------------
-- The shared shape across all four: you, or the toque's organisers, or — when
-- the toque is set to `proponent` — whoever suggested that song.
drop policy if exists "signup select: approved public, else owner/approvers" on public.performance_user;
create policy "signup select: approved public, else owner/approvers" on public.performance_user
  for select to anon, authenticated
  using (
    status = 'approved'
    or user_id = (select auth.uid())
    or exists (
      select 1 from public.performance perf
      join public.party pt on pt.id = perf.party
      where perf.id = performance_user.performance_id
        and (
          public.is_party_admin(pt.id)
          or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
        )
    )
  );

drop policy if exists "signup insert: self, admin, or proponent" on public.performance_user;
create policy "signup insert: self, admin, or proponent" on public.performance_user
  for insert to authenticated
  with check (
    (select perf.band_id from public.performance perf
      where perf.id = performance_user.performance_id) is null
    and (
      user_id = (select auth.uid())
      or exists (
        select 1 from public.performance perf
        join public.party pt on pt.id = perf.party
        where perf.id = performance_user.performance_id
          and (
            public.is_party_admin(pt.id)
            or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
          )
      )
    )
  );

drop policy if exists "signup update: self, admin, or proponent" on public.performance_user;
create policy "signup update: self, admin, or proponent" on public.performance_user
  for update to authenticated
  using (
    band_id is null
    and (
      user_id = (select auth.uid())
      or exists (
        select 1 from public.performance perf
        join public.party pt on pt.id = perf.party
        where perf.id = performance_user.performance_id
          and (
            public.is_party_admin(pt.id)
            or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
          )
      )
    )
  );

drop policy if exists "signup delete: self, admin, or proponent" on public.performance_user;
create policy "signup delete: self, admin, or proponent" on public.performance_user
  for delete to authenticated
  using (
    band_id is null
    and (
      user_id = (select auth.uid())
      or exists (
        select 1 from public.performance perf
        join public.party pt on pt.id = perf.party
        where perf.id = performance_user.performance_id
          and (
            public.is_party_admin(pt.id)
            or (pt.performer_approval = 'proponent' and perf.suggested_by = (select auth.uid()))
          )
      )
    )
  );

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration.
--
-- VERIFY there are none left — this is the query that would have caught the
-- 2026-09-18 outage in one second, and it belongs in the review checklist:
--
--   select c.relname, p.polname
--   from pg_policy p join pg_class c on c.oid = p.polrelid
--   where coalesce(pg_get_expr(p.polqual, p.polrelid), '') like '%party_admin pa%'
--      or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '') like '%party_admin pa%';
--     -> zero rows
--
-- and behaviourally, since these are the signup rules:
--   * a musician can still sign themselves up, and remove themselves
--   * an organizer can still approve, decline and remove anyone
--   * on a `proponent` toque, whoever suggested the song can still do the same
--   * a stranger still cannot, and a band-owned signup is still untouchable
-- =============================================================================
