-- =============================================================================
-- Migration: fix column shadowing in the applause INSERT policy (#38)
-- Date: 2026-09-06
-- =============================================================================
-- SECURITY FIX. The song_performer branch read:
--
--     join public.performance_user pu on pu.performance_id = perf.id
--     where perf.id = performance_id          <-- BUG
--       and pu.user_id = performer_id
--
-- `performance_user` HAS a column named `performance_id`, so the unqualified
-- name bound to `pu.performance_id` rather than to the applause row being
-- inserted. That made the condition identical to the JOIN clause — vacuously
-- true — and the branch degraded from
--
--     "this performer played THIS song"        (intended)
--  to "this performer played SOME started song at this party"  (actual)
--
-- Found by testing: clapping a musician on a song they did not play returned
-- 201 instead of 403, because they had played a different song that night.
--
-- The other branches happened to be safe — neither `performance` nor
-- `performance_user` has a `performer_id`, and `performance` has `party`, not
-- `party_id` — but relying on "no table in scope happens to share this name" is
-- exactly the fragility that caused this. Every reference to the inserted row is
-- now qualified as `applause.<column>`, so adding a column to any joined table
-- later cannot silently re-break a policy.
-- =============================================================================

begin;

drop policy if exists "applause: clap once, in window, valid target" on public.applause;
create policy "applause: clap once, in window, valid target" on public.applause
  for insert to authenticated with check (
    applause.from_user = (select auth.uid())
    and public.can_applaud(applause.party_id)
    and (
      applause.target_type = 'event'
      or (applause.target_type = 'song' and exists (
            select 1 from public.performance perf
            where perf.id = applause.performance_id
              and perf.party = applause.party_id
              and perf.started_at is not null
              and perf.live_state <> 'skipped'))
      or (applause.target_type = 'performer' and exists (
            select 1 from public.performance perf
            join public.performance_user pu on pu.performance_id = perf.id
            where perf.party = applause.party_id
              and pu.user_id = applause.performer_id
              and pu.status = 'approved'))
      or (applause.target_type = 'song_performer' and exists (
            select 1 from public.performance perf
            join public.performance_user pu on pu.performance_id = perf.id
            where perf.id = applause.performance_id
              and perf.party = applause.party_id
              and perf.started_at is not null
              and perf.live_state <> 'skipped'
              and pu.user_id = applause.performer_id
              and pu.status = 'approved'))
    )
  );

commit;
