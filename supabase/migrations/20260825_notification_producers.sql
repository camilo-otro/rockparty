-- =============================================================================
-- Migration: extend notification producers (#51)
-- Date: 2026-08-25  ·  builds on #57 (notifications keystone)
-- =============================================================================
-- The pending/approved/declined transitions already fire (#57). This adds:
--   * a toque going LIVE → its approved performers ("el show está por empezar")
--   * a day-before reminder for CONFIRMED toques → organizer + approved
--     performers, run daily via pg_cron.
-- =============================================================================

begin;

-- Status trigger, now including the `live` case.
create or replace function public.notify_party_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status then
    if new.status = 'confirmed' and old.status = 'pending_venue' and new.created_by is not null then
      insert into public.notification (recipient, type, payload)
      values (new.created_by, 'party_approved',
              jsonb_build_object('party_id', new.id, 'party_title', new.title));

    elsif new.status = 'cancelled'
      and new.cancel_reason in ('venue_declined', 'venue_cancelled')
      and new.created_by is not null then
      insert into public.notification (recipient, type, payload)
      values (new.created_by,
              case when new.cancel_reason = 'venue_declined'
                   then 'party_declined' else 'party_venue_cancelled' end,
              jsonb_build_object('party_id', new.id, 'party_title', new.title, 'reason', new.cancel_note));

    elsif new.status = 'pending_venue' then
      insert into public.notification (recipient, type, payload)
      select uid, 'party_pending_venue',
             jsonb_build_object('party_id', new.id, 'party_title', new.title)
      from (
        select v.created_by as uid from public.venue v
          where v.id = new.venue and v.created_by is not null
        union
        select va.user_id from public.venue_admin va where va.venue_id = new.venue
      ) recips;

    -- The show is starting → everyone approved to play.
    elsif new.status = 'live' then
      insert into public.notification (recipient, type, payload)
      select distinct pu.user_id, 'party_live',
             jsonb_build_object('party_id', new.id, 'party_title', new.title)
      from public.performance perf
      join public.performance_user pu on pu.performance_id = perf.id
      where perf.party = new.id and pu.status = 'approved';
    end if;
  end if;
  return new;
end; $$;

-- Day-before reminder: one 'party_reminder' per (recipient, toque) for confirmed
-- toques happening tomorrow — organizer + approved performers. Deduped so a
-- re-run in the same day can't double-notify.
create or replace function public.notify_upcoming_toques()
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notification (recipient, type, payload)
  select r.uid, 'party_reminder',
         jsonb_build_object('party_id', p.id, 'party_title', p.title, 'date', p.date)
  from public.party p
  join lateral (
    select p.created_by as uid where p.created_by is not null
    union
    select pu.user_id
    from public.performance perf
    join public.performance_user pu on pu.performance_id = perf.id
    where perf.party = p.id and pu.status = 'approved'
  ) r on true
  where p.status = 'confirmed'
    and p.date = (current_date + 1)
    and not exists (
      select 1 from public.notification n
      where n.recipient = r.uid and n.type = 'party_reminder'
        and (n.payload ->> 'party_id')::bigint = p.id
    );
end; $$;

-- Only the scheduler (runs as owner) may fire reminders — not app clients.
revoke execute on function public.notify_upcoming_toques() from public;

commit;

-- --- Scheduling (requires pg_cron) -------------------------------------------
-- If this errors, enable pg_cron via Dashboard > Database > Extensions, then
-- re-run these two lines. cron.schedule is idempotent by job name.
create extension if not exists pg_cron;
select cron.schedule('daily-toque-reminders', '0 14 * * *', $$ select public.notify_upcoming_toques(); $$);
