-- =============================================================================
-- Migration: notify on signup events (#65)
-- Date: 2026-08-26  ·  builds on #57 (notifications keystone)
-- =============================================================================
-- The signup producer family, closing the loop on the #29 approval flow:
--   * a pending request → the approvers (party admins, + the song's proponent in
--     proponent mode) — "alguien quiere tocar X"
--   * approved / declined (pending → …) → the applicant
-- AFTER trigger so it sees the final status set by set_signup_status. Recipient
-- is never the actor. No notification on a self-serve auto-approve (INSERT that
-- lands 'approved') — the actor is the applicant.
-- =============================================================================

begin;

create or replace function public.notify_signup()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint; v_party_title text; v_song_title text;
  v_mode public.performer_approval; v_proponent uuid;
begin
  select perf.party, pt.title, s.title, pt.performer_approval, perf.suggested_by
    into v_party, v_party_title, v_song_title, v_mode, v_proponent
  from public.performance perf
  join public.party pt on pt.id = perf.party
  left join public.song s on s.id = perf.song
  where perf.id = new.performance_id;

  if tg_op = 'INSERT' and new.status = 'pending' then
    insert into public.notification (recipient, type, payload)
    select r.uid, 'signup_requested',
           jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                              'song_title', v_song_title, 'performance_id', new.performance_id)
    from (
      select pt.created_by as uid from public.party pt where pt.id = v_party and pt.created_by is not null
      union
      select pa.user_id from public.party_admin pa where pa.party_id = v_party
      union
      select v_proponent where v_mode = 'proponent' and v_proponent is not null
    ) r
    where r.uid is not null and r.uid <> new.user_id;

  elsif tg_op = 'UPDATE' and new.status is distinct from old.status and old.status = 'pending' then
    if new.status = 'approved' then
      insert into public.notification (recipient, type, payload)
      values (new.user_id, 'signup_approved',
              jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                                 'song_title', v_song_title, 'performance_id', new.performance_id));
    elsif new.status = 'declined' then
      insert into public.notification (recipient, type, payload)
      values (new.user_id, 'signup_declined',
              jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                                 'song_title', v_song_title, 'performance_id', new.performance_id));
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists performance_user_notify on public.performance_user;
create trigger performance_user_notify
  after insert or update on public.performance_user
  for each row execute function public.notify_signup();

commit;
