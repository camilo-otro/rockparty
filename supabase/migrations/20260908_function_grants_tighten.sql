-- =============================================================================
-- Migration: tighten EXECUTE grants on SECURITY DEFINER functions
-- Date: 2026-09-08  (follow-up to 20260908_band_claim_link.sql)
-- =============================================================================
-- REFINES A GOTCHA WE HAD HALF-RIGHT.
--
-- 20260907_purge_revoke_from_public.sql recorded that `revoke ... from anon,
-- authenticated` is a no-op because PUBLIC holds the grant. True — but the
-- converse is ALSO true on this project, and the claim-link migration hit it:
--
--   revoke all on function f from public;   -- necessary, NOT sufficient
--
-- Supabase ships default privileges for this schema:
--
--   pg_default_acl, grantor postgres, schema public, functions:
--     postgres=X/postgres | anon=X/postgres | authenticated=X/postgres | service_role=X/postgres
--
-- So `create function` grants EXECUTE to PUBLIC *and* the default privileges
-- separately grant it to anon and authenticated BY NAME. Revoking PUBLIC leaves
-- the named grants behind. The correct incantation is BOTH:
--
--   revoke all on function f from public, anon, authenticated;
--   grant execute on function f to <only the roles that should have it>;
--
-- Verified after the claim-link migration: anon could EXECUTE band_claim_link,
-- regenerate_band_claim and claim_band_member despite the revoke from public.
-- No live hole — each one checks is_band_manager()/auth.uid() internally and
-- refused anon over REST — but the grant was wider than intended, and the next
-- function written to this pattern might not be as careful.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. The claim-link functions: to their intended roles only
-- ---------------------------------------------------------------------------
revoke all on function public.band_claim_link(bigint)       from public, anon, authenticated;
revoke all on function public.regenerate_band_claim(bigint) from public, anon, authenticated;
revoke all on function public.peek_band_claim(uuid)         from public, anon, authenticated;
revoke all on function public.claim_band_member(uuid)       from public, anon, authenticated;

-- Manager-gated internally; signing in is the outer gate.
grant execute on function public.band_claim_link(bigint)       to authenticated;
grant execute on function public.regenerate_band_claim(bigint) to authenticated;
-- Preview must work signed-OUT: someone opening a link needs to see what they
-- are being asked to join before deciding to create an account.
grant execute on function public.peek_band_claim(uuid)         to anon, authenticated;
-- Claiming requires an account.
grant execute on function public.claim_band_member(uuid)       to authenticated;

-- ---------------------------------------------------------------------------
-- 2. notify_upcoming_toques: pg_cron only
-- ---------------------------------------------------------------------------
-- Found while auditing the above, and the one case with real (if small) impact
-- rather than just an over-broad grant: this is the daily 14:00 reminder job
-- (#35/#57), it INSERTS into public.notification, and anon could invoke it over
-- REST. It is idempotent — a `not exists` guard stops duplicate party_reminder
-- rows — so the worst an attacker achieves is firing tomorrow's reminders early,
-- once. Still an unauthenticated write to a user-facing table that nothing
-- should be able to trigger but the scheduler.
--
-- pg_cron runs as postgres, which keeps EXECUTE as the function owner.
revoke all on function public.notify_upcoming_toques() from public, anon, authenticated;

commit;

-- =============================================================================
-- Deliberately NOT changed here
-- =============================================================================
-- Every other SECURITY DEFINER function in public is likewise anon-executable
-- via the same default privileges, but each one is internally guarded and a
-- direct anon call is refused:
--
--   is_dev / is_band_manager / is_party_admin / can_sign_up_band / can_applaud
--       predicates; return false for anon.
--   sign_band_up            -> "not allowed to sign up this band"
--   set_band_signup_status  -> checks the approver set after the state lookup
--   add_band_creator_as_manager, notify_party_status, notify_signup,
--   party_admin_presentation_guard
--       trigger functions; a direct call has no NEW/OLD and errors.
--
-- Tightening those is defense-in-depth on code that already defends itself, and
-- it belongs in its own change rather than riding along with the claim link.
-- Tracked separately.
-- =============================================================================
