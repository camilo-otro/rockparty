-- =============================================================================
-- Migration: band approval as a unit (#74, epic #40)
-- Date: 2026-09-03
-- =============================================================================
-- A band signup lands as many pending performance_user rows sharing
-- (performance_id, band_id). #74 approves/declines the whole act in ONE action
-- with ONE notification (band-or-nothing, v1). notify_signup skips band rows and
-- the client can't insert notifications, so this is a SECURITY DEFINER RPC:
-- it authorizes the caller (party admin, or the proponent in proponent mode —
-- matching set_signup_status), flips all the band's pending rows together, and
-- notifies the signer once. The set_signup_status BEFORE-UPDATE trigger still
-- runs and re-checks auth.uid() (the real caller survives SECURITY DEFINER), so
-- authorization is enforced twice.
--
-- Decline keeps the rows (status='declined'); the setlist hides a fully-declined
-- band-owned song. Nothing is deleted — the organizer's history is preserved.
-- =============================================================================

begin;

create or replace function public.set_band_signup_status(
  p_performance bigint, p_band bigint, p_status public.signup_status
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_party bigint; v_party_title text; v_song_title text; v_band_name text;
  v_signer uuid; v_mode public.performer_approval;
  v_uid uuid := (select auth.uid());
  v_n int;
begin
  if p_status not in ('approved', 'declined') then
    raise exception 'invalid status';
  end if;

  select perf.party, pt.title, s.title, b.name, perf.suggested_by, pt.performer_approval
    into v_party, v_party_title, v_song_title, v_band_name, v_signer, v_mode
  from public.performance perf
  join public.party pt on pt.id = perf.party
  left join public.song s on s.id = perf.song
  join public.band b on b.id = p_band
  where perf.id = p_performance and perf.band_id = p_band;
  if not found then
    raise exception 'band is not signed up for this song';
  end if;

  -- Same approver set as set_signup_status / the per-row UI: party creator,
  -- party admin, or (in proponent mode) the song's proponent.
  if not (
       exists (select 1 from public.party pt where pt.id = v_party and pt.created_by = v_uid)
    or exists (select 1 from public.party_admin pa where pa.party_id = v_party and pa.user_id = v_uid)
    or (v_mode = 'proponent' and v_signer = v_uid)
  ) then
    raise exception 'not allowed to decide this signup';
  end if;

  update public.performance_user
    set status = p_status
    where performance_id = p_performance and band_id = p_band and status = 'pending';
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return;                                  -- nothing pending; don't double-notify
  end if;

  -- One notification to the signer (never the actor deciding their own).
  if v_signer is not null and v_signer <> v_uid then
    insert into public.notification (recipient, type, payload)
    values (v_signer,
            case when p_status = 'approved' then 'band_signup_approved' else 'band_signup_declined' end,
            jsonb_build_object('party_id', v_party, 'party_title', v_party_title,
                               'band_id', p_band, 'band_name', v_band_name,
                               'song_title', v_song_title, 'performance_id', p_performance));
  end if;
end; $$;

commit;
