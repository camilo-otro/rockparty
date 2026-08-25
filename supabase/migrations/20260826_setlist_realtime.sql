-- =============================================================================
-- Migration: live setlist via Realtime (#63, second slice)
-- Date: 2026-08-26
-- =============================================================================
-- Add performance + performance_user to the supabase_realtime publication so the
-- party detail page can refresh the setlist live when another user adds/removes a
-- song, signs up, or is approved. RLS still applies to Realtime, so subscribers
-- only receive rows they can SELECT (approved signups public; pending/declined to
-- approvers).
-- =============================================================================

begin;
alter publication supabase_realtime add table public.performance;
alter publication supabase_realtime add table public.performance_user;
commit;
