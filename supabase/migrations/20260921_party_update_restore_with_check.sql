-- =============================================================================
-- Migration: restore `with check (true)` on party's UPDATE policy
-- Date: 2026-09-21
-- =============================================================================
-- CORRECTIVE. Apply right after 20260921_party_policy_no_inline_subquery.sql.
--
-- -----------------------------------------------------------------------------
-- My mistake
-- -----------------------------------------------------------------------------
-- That migration replaced an inlined party_admin subquery with is_party_admin,
-- and was advertised — in its own comments — as behaviour-preserving. It was
-- not, in one respect I asserted without checking:
--
--   "No WITH CHECK, same as before: Postgres reuses USING for the check when it
--    is omitted"
--
-- The first half is true. The second is not: the original policy DID declare
-- `with check (true)`, which schema.sql records. Omitting it does not preserve
-- that — it silently swaps a check of `true` for a check of the USING clause.
--
-- The effect: previously ANY resulting row was accepted. After that migration
-- the resulting row also had to satisfy `is_party_admin(id) or
-- is_venue_admin(venue)`. So a venue admin who is neither the creator nor a
-- party admin could no longer move a toque to a venue they do not administer —
-- which they could before.
--
-- -----------------------------------------------------------------------------
-- Why restore rather than keep it
-- -----------------------------------------------------------------------------
-- The tightening is arguably an improvement: an UPDATE policy whose WITH CHECK
-- is `true` lets someone edit a row into a state they no longer control, and
-- "you must still own the result" is the safer rule.
--
-- But it was not decided, it was a side effect of a refactor that said it
-- changed nothing. Tightening a policy is worth doing deliberately, with its own
-- reasoning about who it stops — not smuggled in under a rename. Restoring
-- fidelity first keeps the two changes separable, and leaves the question open
-- on its merits rather than answered by accident.
-- =============================================================================

begin;

drop policy if exists "allow update to party admins" on public.party;
create policy "allow update to party admins" on public.party
  for update to authenticated
  using (
    public.is_party_admin(id)
    or public.is_venue_admin(venue)
  )
  with check (true);

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql (USING changes, WITH CHECK does
-- not). No type regeneration.
--
-- VERIFY:
--   select pg_get_expr(polqual, polrelid)      as using_expr,
--          pg_get_expr(polwithcheck, polrelid) as check_expr
--   from pg_policy p join pg_class c on c.oid = p.polrelid
--   where c.relname = 'party' and p.polcmd = 'w';
--     -> using  (is_party_admin(id) OR is_venue_admin(venue))
--     -> check  true
-- =============================================================================
