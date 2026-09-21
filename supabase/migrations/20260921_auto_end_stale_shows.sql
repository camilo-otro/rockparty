-- =============================================================================
-- Migration: a show that nobody ended closes itself after 12 hours (#37)
-- Date: 2026-09-21
-- =============================================================================
-- ADDITIVE. Safe to apply at any time; no client change goes with it.
--
-- -----------------------------------------------------------------------------
-- Why
-- -----------------------------------------------------------------------------
-- "End the show" is the last thing anyone remembers to tap. The organiser is
-- packing up a room, not looking at a phone, and nothing in the app pushes them
-- to close it. Measured before writing this:
--
--   Jojoprueba (a REAL toque, dated 2026-09-06)   live for 351 hours
--
-- Fourteen days of a toque telling everyone it is happening right now.
--
-- -----------------------------------------------------------------------------
-- What it does, and what it deliberately does not
-- -----------------------------------------------------------------------------
-- Exactly what end_show does, minus the person:
--
--   * the song left `playing` is closed — marked played, ended_at set
--   * the toque goes to `completed`
--
-- It does NOT touch songs still `queued`. A set that never got played did not
-- get played, and inventing history to tidy the row would be worse than the
-- untidy row. The recap is meant to show what actually happened, skips and all.
--
-- It also does not notify anyone. notify_party_status fires on `confirmed`,
-- `cancelled`, `pending_venue` and `live` — `completed` is silent — so this
-- cannot ping a room full of musicians at four in the morning. Worth keeping
-- that way if a "show ended" notification is ever added: an automatic close is
-- not news.
--
-- -----------------------------------------------------------------------------
-- Twelve hours from WHAT
-- -----------------------------------------------------------------------------
-- From `status_changed_at`, which the party_status_changed trigger sets on every
-- status change — so for a live toque it is the moment the show started. Not
-- from `party.date`, which is a DATE with no time and would close a show that
-- started at 23:00 almost immediately.
--
-- Hourly, not daily like the other two jobs: a daily sweep would let a show run
-- up to 36 hours before the rule caught it, which makes "12 hours" meaningless.
-- Hourly means the real window is 12 to 13 hours.
-- =============================================================================

begin;

create or replace function public.auto_end_stale_shows()
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_n int;
begin
  -- BEFORE the status flip: this selects on p.status = 'live', so closing the
  -- songs afterwards would match nothing.
  --
  -- ended_at is the moment the show was DEEMED over, not the moment the job
  -- happened to notice. end_show uses now() and is right to — a person ending it
  -- is ending it now. Here they are not the same: the backlog this was written
  -- for had been live 351 hours, and now() would record a song from two weeks
  -- ago as having finished today. The cutoff is also stable, so a re-run cannot
  -- drag the timestamp forward.
  update public.performance perf
  set live_state = 'played',
      ended_at = p.status_changed_at + interval '12 hours'
  from public.party p
  where p.id = perf.party
    and p.status = 'live'
    and perf.live_state = 'playing'
    and now() > p.status_changed_at + interval '12 hours';

  update public.party
  set status = 'completed'
  where status = 'live'
    and now() > status_changed_at + interval '12 hours';

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

-- Same lockdown as the other two cron functions: postgres and service_role only.
-- `revoke from anon, authenticated` would be a no-op here — they inherit EXECUTE
-- from PUBLIC, so PUBLIC is the grant that has to go.
revoke all on function public.auto_end_stale_shows() from public, anon, authenticated;

select cron.schedule(
  'auto-end-stale-shows',
  '0 * * * *',
  $$ select public.auto_end_stale_shows(); $$
);

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration (the
-- function is not callable from the client).
--
-- VERIFY:
--   select jobname, schedule from cron.job;
--     -> auto-end-stale-shows, hourly
--
--   select id, title, status,
--          round(extract(epoch from (now() - status_changed_at))/3600.0, 1) as hours
--   from party where status = 'live';
--     -> nothing over 13 hours, once the job has run
--
-- KNOWN CONSEQUENCE, not handled here: start_show only accepts a toque whose
-- status is 'confirmed' or 'live', so once this closes a show the organiser
-- cannot reopen it from the app. Twelve hours is long for a jam night, but if
-- a show ever legitimately runs longer the only way back is the SQL editor.
-- Widening start_show to accept 'completed' would double as an undo for ending
-- the show by mistake — deliberately left out of this migration rather than
-- changed quietly along with it.
-- =============================================================================
