-- =============================================================================
-- Migration: one RPC for the profile-menu flags (#101)
-- Date: 2026-09-10
-- =============================================================================
-- A signed-in user's cold load fired FIVE requests just to decide which entries
-- to render in the profile menu:
--
--   1. POST /auth/v1/user            -- refreshDev() called with no uid
--   2. dev_user   ?user_id=eq.<me>
--   3. venue      ?created_by=eq.<me>
--   4. venue_admin?user_id=eq.<me>
--   5. song_moderator?user_id=eq.<me>
--
-- None of it is latency — they all fire without await, so they are concurrent —
-- but it is five round trips against a free-tier request budget, and the count
-- grew from two to five across three features. The next menu entry needing a
-- permission check would have made it six. This collapses them to one.
--
-- Request 1 was pure waste: the layout already holds session.user.id and passes
-- it to the other refreshers on the very next line. That is fixed on the client
-- side, by passing the uid it already has.
-- =============================================================================

begin;

-- SECURITY DEFINER for two reasons, neither of them "speed":
--
--   * The answer should not depend on the SELECT policies of four different
--     tables. `venue` in particular is filtered by (is_test = false or is_dev()),
--     so a plain client query answers a subtly different question than the one
--     being asked.
--   * It exposes nothing new. Every output is a boolean about auth.uid()'s own
--     rows, all of which the caller could already determine by querying those
--     tables directly (dev_user and song_moderator both have self-read policies;
--     venue_admin's SELECT policy is `true`).
--
-- Returns exactly one row, all false for an anonymous caller (auth.uid() is
-- null, so every EXISTS is false).
create or replace function public.my_user_flags()
returns table (
  is_dev            boolean,
  manages_venue     boolean,
  is_song_moderator boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with d as (
    select (select auth.uid()) as uid,
           exists (
             select 1 from public.dev_user dv where dv.user_id = (select auth.uid())
           ) as dev
  )
  select
    d.dev,
    -- Two halves because venues have NO creator-auto-add trigger (unlike parties
    -- and bands): most venues have a created_by and no venue_admin row at all,
    -- so "manages a venue" genuinely means either one.
    --
    -- Both halves check is_test, which the old client code did NOT do on the
    -- venue_admin side. Without it an admin row pointing at a test venue would
    -- light up "Mis locales" while /venues/mine — which reads under RLS — showed
    -- an empty page. Verified against live data: this changes no current answer
    -- (all five venue managers compute identically either way), so it is closing
    -- a latent inconsistency, not altering behaviour.
    exists (
      select 1 from public.venue v
       where v.created_by = d.uid
         and (v.is_test = false or d.dev)
    )
    or exists (
      select 1 from public.venue_admin va
       join public.venue v on v.id = va.venue_id
       where va.user_id = d.uid
         and (v.is_test = false or d.dev)
    ),
    exists (
      select 1 from public.song_moderator m where m.user_id = d.uid
    )
  from d;
$$;

-- Both halves of the grant gotcha (see 20260908_function_grants_tighten.sql):
-- `create function` grants EXECUTE to PUBLIC, and Supabase's pg_default_acl
-- grants it to anon and authenticated BY NAME, so revoking PUBLIC alone leaves
-- the named grants behind. anon has no use for this — it would get three
-- falses — so it is not granted.
revoke all on function public.my_user_flags() from public, anon, authenticated;
grant execute on function public.my_user_flags() to authenticated;

commit;

-- =============================================================================
-- The single-purpose helpers is_dev(), is_song_moderator() and
-- song_on_real_setlist() all STAY. They are used inside RLS policies, which is
-- a different job from this one -- this function is a display convenience for
-- the client and is not an authorization boundary. Nothing that matters is
-- decided by its return value; RLS still decides every read and write.
--
-- supabase/schema.sql and src/lib/database.types.ts are updated in the same
-- commit. Re-run the generator after applying to confirm they match.
--
-- To verify over REST:
--   rpc/my_user_flags as the moderator -> all three true
--   rpc/my_user_flags with an anon token -> 42501 (not granted)
-- =============================================================================
