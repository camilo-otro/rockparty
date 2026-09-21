-- =============================================================================
-- Migration: going private keeps the people who already said they were coming
-- Date: 2026-09-21  (#113 part B)
-- =============================================================================
-- ADDITIVE. No client change. No effect until a toque is actually flipped to
-- private, which nothing can do yet.
--
-- -----------------------------------------------------------------------------
-- The rule
-- -----------------------------------------------------------------------------
-- Someone who RSVP'd while a toque was public was told they were going. Turning
-- the toque private afterwards would silently take that back — they would stop
-- seeing the toque at all, with no notice and no way to ask. That is hostile,
-- and it is the sort of thing people only notice on the night.
--
-- So flipping to private converts every existing RSVP into an invite. The guest
-- keeps exactly what they had; the organiser gets a list they can then prune
-- deliberately, which is a different act from a silent revocation.
--
-- -----------------------------------------------------------------------------
-- Why a trigger and not the client
-- -----------------------------------------------------------------------------
-- It is a data rule, not a screen rule: whatever changes `visibility` — the edit
-- form, a future bulk action, the SQL editor — has to preserve it, and a trigger
-- is the only place that is true. It is also atomic with the flip, so there is
-- no window where the toque is private and its guests are locked out.
--
-- Idempotent on purpose (`on conflict do nothing`): public -> private -> public
-- -> private re-converts without duplicating, and an already-invited guest is
-- left alone.
--
-- -----------------------------------------------------------------------------
-- What this does NOT do
-- -----------------------------------------------------------------------------
-- It does not revoke anything when a toque goes the other way. Someone invited
-- to a private toque that later becomes public keeps their invite — harmless,
-- since everyone can see it anyway, and it means flipping back and forth does
-- not quietly shed people.
--
-- It also does not touch the OTHER direction of #114: a PUBLIC toque at a
-- private venue still hands its address to anyone who RSVPs. That is the
-- organiser's choice and the remedy is to make the toque private — but it is
-- worth being clear that "private venue" alone was never the boundary.
-- =============================================================================

begin;

create or replace function public.keep_rsvps_as_invites()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.visibility = 'private' and old.visibility is distinct from 'private' then
    insert into public.party_invite (party_id, user_id, invited_by)
    select new.id, r.user_id, new.created_by
    from public.party_rsvp r
    where r.party_id = new.id
    on conflict (party_id, user_id) do nothing;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_keep_rsvps_as_invites on public.party;
create trigger trg_keep_rsvps_as_invites
  after update of visibility on public.party
  for each row execute function public.keep_rsvps_as_invites();

revoke all on function public.keep_rsvps_as_invites() from public, anon, authenticated;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration (the
-- function is a trigger and is not callable from the client).
--
-- VERIFY, on a test toque that has RSVPs:
--   update party set visibility = 'private' where id = <test toque>;
--   select * from party_invite where party_id = <test toque>;
--     -> one row per person who had RSVP'd, invited_by = the organiser
--   and as one of those people over REST: the toque is still visible
--
-- then put it back:
--   update party set visibility = 'public' where id = <test toque>;
--     -> the invites remain, deliberately
-- =============================================================================
