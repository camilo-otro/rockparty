-- =============================================================================
-- Migration: party_admin's policies stop reading party_admin (#113)
-- Date: 2026-09-21
-- =============================================================================
-- URGENT — APPLY IMMEDIATELY. Creating a toque is broken in production right
-- now. Behaviour-preserving otherwise: the same people, evaluated without RLS.
--
-- -----------------------------------------------------------------------------
-- The failure
-- -----------------------------------------------------------------------------
--   POST /party  ->  42P17 infinite recursion detected in policy
--                    for relation "party_admin"
--
-- Creating a toque fires auto_add_admin, which is SECURITY INVOKER, so the row
-- it inserts into party_admin is subject to party_admin's INSERT policy. That
-- policy inlines party_admin:
--
--   (select created_by from party where id = party_admin.party_id) = auth.uid()
--   or exists (select 1 from party_admin pa
--              where pa.party_id = party_admin.party_id
--                and pa.user_id = auth.uid())
--
-- Reading party_admin there applies party_admin's SELECT policy, so evaluating a
-- policy ON party_admin requires evaluating a policy ON party_admin. Postgres
-- refuses.
--
-- -----------------------------------------------------------------------------
-- I broke this on 2026-09-18, and this is the third time the same rule has bitten
-- -----------------------------------------------------------------------------
-- The inline subqueries are old. They were harmless while party_admin's SELECT
-- was `using (true)` — reading it resolved to a constant and went no further.
-- Narrowing that policy (to make `hidden` mean something) gave it a body, and
-- the body closed the loop.
--
-- I noticed the RISK while writing the spec, fixed `party`'s two policies for
-- exactly this reason, and wrote in that migration that the other eight
-- inlinings were "a consistency problem worth its own pass, not a cycle."
-- That was wrong about party_admin's own two: a policy that reads its OWN table
-- does not need any help from another table to recurse. I checked the chains
-- that ran THROUGH party_admin and never checked the ones that started there.
--
-- CLAUDE.md states the rule plainly — a table referenced inside a policy is read
-- AS THE CALLING USER, so use the DEFINER helper. These two are the last
-- policies on party_admin that ignore it.
--
-- -----------------------------------------------------------------------------
-- Same people, exactly
-- -----------------------------------------------------------------------------
-- is_party_admin(pid) IS `created_by = auth.uid() or exists(party_admin ...)` —
-- both clauses of the INSERT check, in one DEFINER call that reads with the
-- owner's rights and so triggers no policy at all.
--
-- The other six inlinings (performance x2, performance_user x4) are left alone:
-- they read party_admin from a policy on a DIFFERENT relation, so the chain runs
-- party_admin -> can_see_party -> party -> DEFINER helpers and terminates. Still
-- worth a consistency pass; still not a cycle. This time I checked.
-- =============================================================================

begin;

drop policy if exists "allow Insert to party owner and other party admins" on public.party_admin;
create policy "party_admin: organisers add organisers" on public.party_admin
  for insert to authenticated
  with check (public.is_party_admin(party_id));

drop policy if exists "Enable delete for party admins" on public.party_admin;
create policy "party_admin: organisers remove, or you remove yourself" on public.party_admin
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    or public.is_party_admin(party_id)
  );

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration.
--
-- VERIFY, as a signed-in user — this is the exact call that fails today:
--   POST /party {"title":"…","date":"…","venue":…}
--     -> succeeds, and the creator lands in party_admin via auto_add_admin
--
-- and confirm the rest still holds:
--   a co-organiser can still add and remove other organisers
--   a non-organiser still cannot
-- =============================================================================
