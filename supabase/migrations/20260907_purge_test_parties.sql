-- =============================================================================
-- Migration: auto-purge stale TEST toques (#67 follow-up)
-- Date: 2026-09-07
-- =============================================================================
-- Test data accumulates fast and clutters the dev view. This deletes test toques
-- once they are done with:
--   * cancelled, and cancelled more than a day ago
--   * or dated before today (the event has passed)
--
-- Future-dated test toques are kept, however old the row is, so work in progress
-- survives. Drafts follow the same rule: kept while the date is ahead.
--
-- DESTRUCTIVE AND UNRECOVERABLE. Every FK into party is ON DELETE CASCADE, so a
-- single delete also removes that toque's performances, signups, RSVPs, admin
-- rows and applause. There is no soft-delete and no undo.
--
-- The `is_test = true` predicate is the ONLY thing standing between this job and
-- real events. It appears in the delete itself, not in a helper or a view, so it
-- cannot be refactored away by accident.
--
-- On the "a dev mis-flags a real toque" worry: it is not much of one, because
-- is_test = true already hides the toque from every non-dev (#67). Such an event
-- is broken long before this job runs — nobody can open the link, so the flag
-- gets noticed and fixed while the date is still ahead, which is exactly the
-- case this job keeps. The purge only removes toques that already failed to be
-- usable by real people.
-- =============================================================================

begin;

create or replace function public.purge_stale_test_parties()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted integer;
begin
  delete from public.party p
  where p.is_test = true                         -- the whole safety boundary
    and (
      -- cancelled, and it has been a day
      (p.status = 'cancelled' and p.status_changed_at < now() - interval '1 day')
      -- or the event date has passed
      or (p.date is not null and p.date < current_date)
    );

  get diagnostics v_deleted = row_count;

  -- Shows up in cron.job_run_details, so a run that suddenly removes far more
  -- than usual is visible after the fact.
  raise notice 'purge_stale_test_parties: deleted % test toque(s)', v_deleted;
  return v_deleted;
end;
$$;

comment on function public.purge_stale_test_parties() is
  'Deletes test toques that are cancelled (>1 day) or past-dated. Cascades to their setlists, signups, RSVPs and applause. Scheduled daily via pg_cron.';

-- Not callable from the client: this is a cron-only maintenance routine and
-- there is no reason for a browser to be able to trigger a bulk delete.
revoke all on function public.purge_stale_test_parties() from anon, authenticated;

-- Daily, an hour after the toque reminders (job 'daily-toque-reminders', 14:00).
select cron.unschedule('purge-stale-test-parties')
where exists (select 1 from cron.job where jobname = 'purge-stale-test-parties');

select cron.schedule(
  'purge-stale-test-parties',
  '0 15 * * *',
  $$ select public.purge_stale_test_parties(); $$
);

commit;
