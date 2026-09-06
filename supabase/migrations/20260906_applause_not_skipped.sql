-- =============================================================================
-- Migration: skipped songs are not clappable (#38)
-- Date: 2026-09-06
-- =============================================================================
-- The clap gate was `started_at is not null`, which let a SKIPPED song through.
-- That timestamp is an artifact of how live mode works — skip_song only ever
-- marks the song that is currently `playing`, so it always has a start time —
-- not evidence anyone performed it. Tapping "Saltar" means it didn't happen.
--
-- Timestamps are deliberately NOT cleared on skip: "we reached this song at
-- 22:15 and skipped it" is real history, and Stage 3 will want it. The gate
-- checks live_state explicitly instead.
--
-- Claps placed while the song WAS playing are left alone. Someone clapped
-- something they heard; deleting that would be rewriting their opinion. Such a
-- song shows its tally read-only, which is the shape the UI already has.
-- =============================================================================

begin;

drop policy if exists "applause: clap once, in window, valid target" on public.applause;
create policy "applause: clap once, in window, valid target" on public.applause
  for insert to authenticated with check (
    from_user = (select auth.uid())
    and public.can_applaud(party_id)
    and (
      target_type = 'event'
      or (target_type = 'song' and exists (
            select 1 from public.performance perf
            where perf.id = performance_id
              and perf.party = party_id
              and perf.started_at is not null
              and perf.live_state <> 'skipped'))
      or (target_type = 'performer' and exists (
            select 1 from public.performance perf
            join public.performance_user pu on pu.performance_id = perf.id
            where perf.party = party_id
              and pu.user_id = performer_id
              and pu.status = 'approved'))
      or (target_type = 'song_performer' and exists (
            select 1 from public.performance perf
            join public.performance_user pu on pu.performance_id = perf.id
            where perf.id = performance_id
              and perf.party = party_id
              and perf.started_at is not null
              and perf.live_state <> 'skipped'
              and pu.user_id = performer_id
              and pu.status = 'approved'))
    )
  );

commit;
