-- =============================================================================
-- Migration: live notification bell via Realtime (#63, first slice)
-- Date: 2026-08-26
-- =============================================================================
-- Add the notification table to the supabase_realtime publication so clients can
-- subscribe to inserts and update the header bell without a refresh. RLS still
-- applies to Realtime, so a subscriber only receives their own notifications.
-- =============================================================================

begin;
alter publication supabase_realtime add table public.notification;
commit;
