-- =============================================================================
-- Migration: party's policies stop inlining a party_admin subquery (#113 part B)
-- Date: 2026-09-21
-- =============================================================================
-- ADDITIVE / BEHAVIOUR-PRESERVING. No client change. The predicate is the same
-- set of people; only how it is evaluated changes.
--
-- -----------------------------------------------------------------------------
-- Why now
-- -----------------------------------------------------------------------------
-- Both policies on `party` contain:
--
--   created_by = (select auth.uid())
--   OR exists (select 1 from party_admin pa
--              where pa.party_id = party.id and pa.user_id = (select auth.uid()))
--
-- CLAUDE.md is explicit that a table referenced inside a policy is read AS THE
-- CALLING USER, which is why every other guard in this schema is a DEFINER
-- helper. These two predate that rule, and were harmless while party_admin had
-- no real policy.
--
-- That changed on 2026-09-18. party_admin's SELECT is now:
--
--   user_id = auth.uid() OR is_party_admin(party_id)
--   OR (hidden = false AND can_see_party(party_id))
--
-- and can_see_party is SECURITY INVOKER — deliberately, since it works by asking
-- whether a party row is visible TO THE CALLER. So reading party_admin from
-- inside party's policy can reach back into party's policy:
--
--   party -> party_admin -> can_see_party -> party -> ...
--
-- which is what "infinite recursion detected in policy for relation" means.
--
-- -----------------------------------------------------------------------------
-- Why it has not fired
-- -----------------------------------------------------------------------------
-- The subquery restricts to `pa.user_id = auth.uid()`, which is also the FIRST
-- disjunct of party_admin's policy, so every row that reaches the check already
-- satisfies it and the OR short-circuits before can_see_party is evaluated.
--
-- That is a planner-ordering accident, not a guarantee. The app has been in
-- continuous use since the 18th, so it is holding — but it is one clause away
-- from not holding, and part B adds a clause to exactly this policy.
--
-- -----------------------------------------------------------------------------
-- Why fixing `party` alone is enough
-- -----------------------------------------------------------------------------
-- TEN policies across five tables inline this subquery (party x2, party_admin
-- x2, performance x2, performance_user x4). They are all the same smell, but
-- only `party` closes a cycle: any chain runs X -> party_admin -> can_see_party
-- -> party, and terminates there as soon as party's own policy stops reading a
-- table under RLS. is_party_admin and is_venue_admin are both SECURITY DEFINER,
-- so they read with the owner's rights and no policy applies inside them.
--
-- The other eight are a consistency problem worth its own pass, not a cycle.
--
-- -----------------------------------------------------------------------------
-- Same people, exactly
-- -----------------------------------------------------------------------------
-- is_party_admin(pid) is `created_by = auth.uid() OR exists(party_admin ...)` —
-- literally the two clauses being replaced, in one call. It is executable by
-- anon, which the SELECT policy requires since that policy applies `to anon`;
-- a policy calling a function the caller cannot execute raises permission
-- denied rather than evaluating false.
-- =============================================================================

begin;

drop policy if exists "select party: public statuses or owner/admins" on public.party;
create policy "select party: public statuses or owner/admins" on public.party
  for select to anon, authenticated
  using (
    (
      status in ('confirmed', 'live', 'completed')
      or public.is_party_admin(id)
      or public.is_venue_admin(venue)
    )
    and (is_test = false or public.is_dev())
  );

-- No WITH CHECK, same as before: Postgres reuses USING for the check when it is
-- omitted, and an admin cannot move a toque out of their own reach anyway.
drop policy if exists "allow update to party admins" on public.party;
create policy "allow update to party admins" on public.party
  for update to authenticated
  using (
    public.is_party_admin(id)
    or public.is_venue_admin(venue)
  );

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration.
--
-- VERIFY as an ANONYMOUS caller (nothing should change):
--   /party?select=id,title,status    -> the same confirmed/live/completed toques
--   /party?select=id&is_test=eq.true -> still empty
--
-- and as a SIGNED-IN organiser:
--   a draft/pending toque you created or co-organise is still visible
--   a draft you have nothing to do with is still not
-- =============================================================================
