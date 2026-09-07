-- =============================================================================
-- Migration: actually lock down purge_stale_test_parties() (#67 follow-up)
-- Date: 2026-09-07
-- =============================================================================
-- SECURITY FIX. The previous migration tried to keep this SECURITY DEFINER bulk
-- delete off the API with:
--
--     revoke all on function public.purge_stale_test_parties() from anon, authenticated;
--
-- That did nothing useful. `create function` grants EXECUTE to **PUBLIC** by
-- default, and anon/authenticated inherit from PUBLIC — so the revoke removed
-- role-specific grants they never separately held, and left the real one:
--
--     proacl = {=X/postgres, postgres=X/postgres, service_role=X/postgres}
--                ^^^^^^^^^^ empty grantee = PUBLIC still has EXECUTE
--
-- Net effect: /rest/v1/rpc/purge_stale_test_parties was callable by ANON with
-- the public key, deleting every stale test toque on demand. Bounded to test
-- data by the is_test predicate, so not catastrophic — but an unauthenticated
-- destructive endpoint nobody asked for.
--
-- PUBLIC is the grant that has to go. postgres and service_role keep EXECUTE,
-- which is what pg_cron runs as, so the scheduled job is unaffected.
--
-- Worth remembering for any future SECURITY DEFINER function: revoking from
-- anon/authenticated alone is a no-op. Revoke from PUBLIC.
-- =============================================================================

begin;

revoke all on function public.purge_stale_test_parties() from public;
revoke all on function public.purge_stale_test_parties() from anon, authenticated;

commit;
