-- =============================================================================
-- Migration: drop profile.role and the role table (#99)
-- Date: 2026-09-11
-- =============================================================================
-- ############################################################################
-- ##  DEPLOY THE CLIENT FIRST. THIS ONE IS BACKWARDS FROM THE USUAL ORDER.  ##
-- ############################################################################
--
-- Every other migration in this project is additive, so applying it early is
-- harmless. This one DROPS a column the CURRENT production client still selects,
-- and the failure is not a degradation — it is an outage for every signed-in
-- user:
--
--   src/routes/+layout.js does `select('id, role, nickname')` and then
--   `if (!dbUser || !dbUser.nickname) { ... throw redirect('/performers/<id>/edit') }`
--
-- A missing column makes that select fail, `dbUser` comes back null, and EVERY
-- LOGGED-IN USER IS REDIRECTED INTO THE PROFILE-CREATION FORM ON EVERY PAGE
-- LOAD, until the new client ships.
--
-- Correct order:
--   1. Merge and deploy the client (it selects `id, nickname` — works fine
--      whether or not the column still exists).
--   2. THEN run this.
--
-- IRREVERSIBLE. Read the loss statement below before running.
--
-- #99 was filed as "profile.role is user-writable and cannot gate anything" —
-- the `profile` UPDATE policy is USING (id = auth.uid()) with no WITH CHECK, so
-- Postgres reuses USING as the check, and `authenticated` holds UPDATE on the
-- `role` column. Any signed-in user could run:
--
--   update profile set role = 1 where id = auth.uid();
--
-- The proposed fix was column-level grants, the profile.email pattern from #47.
-- Auditing it first showed that is the wrong fix, because the column is not used
-- for anything at all:
--
--   RLS policies referencing profile.role .............. none
--   DB functions or triggers referencing it ............ none
--   Client code reading it ............................. none
--   Reads of the `role` lookup table ................... none, ever
--
-- It IS fetched — src/routes/+layout.js selects `id, role, nickname` and puts
-- role into the `user` store — and then nothing ever reads `$user.role`. A round
-- trip's worth of bytes, discarded.
--
-- So the risk was never escalation through it. The risk is that
-- `profile.role = 1` LOOKS exactly like an admin flag, with a `role` table
-- spelling out admin / venue_owner / user to make it convincing, and it is the
-- first thing anyone reaches for. It was the first thing reached for while
-- building song moderation (#100), and it only failed to become the gate there
-- because someone checked whether it held.
--
-- Locking it down would leave a well-defended decoy. Deleting it means the decoy
-- stops existing. dev_user and song_moderator are the real pattern — grant-only
-- tables with no self-insert policy — and they already work.
--
-- Product decision recorded alongside this: role is derivable from usage
-- (organised a toque, manages a venue, plays in a band), and dev is the only
-- restriction that currently matters.
--
-- -----------------------------------------------------------------------------
-- WHAT IS LOST
-- -----------------------------------------------------------------------------
-- profile.role, 21 values:
--     3 ('user')   x20  <- the column DEFAULT, so nobody assigned these
--     1 ('admin')  x1   <- one account, set by hand long ago
--
-- public.role, 3 rows:  1=admin, 2=venue_owner, 3=user
--
-- No trigger, no signup path and no application logic ever maintained any of it.
-- Nothing derivable is being destroyed: who organises, who manages a venue and
-- who plays is all still in party, venue, venue_admin, band_member and
-- party_requirement.
-- =============================================================================

begin;

-- Dependency check done first, not assumed: the only things pointing at either
-- object are the FK, the index, and the role table's own SELECT policy. No
-- views, no other foreign keys, neither table is in the realtime publication.
-- Dropping the table takes its policy with it.
drop index if exists public.idx_profile_role;

alter table public.profile drop constraint if exists user_role_fkey;
alter table public.profile drop column if exists role;

drop table if exists public.role;

commit;

-- =============================================================================
-- After applying: regenerate src/lib/database.types.ts and reconcile
-- supabase/schema.sql.
--
-- Verify: a signed-in user loads any page and is NOT bounced to
-- /performers/<id>/edit. That is the symptom of running this too early.
-- =============================================================================
