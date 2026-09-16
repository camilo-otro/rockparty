-- =============================================================================
-- Migration: make the venue address fix hold for NEW venues too (#113)
-- Date: 2026-09-16
-- =============================================================================
-- SAFE TO APPLY NOW, before any client deploy. It is designed to work while the
-- client still writes the old columns, which is the whole point.
--
-- -----------------------------------------------------------------------------
-- The hole
-- -----------------------------------------------------------------------------
-- 20260916_venue_contact_privacy.sql closed the leak for the rows that existed:
-- it copied the contact columns into venue_contact and blanked them on private
-- venues. But that was a ONE-TIME UPDATE, `venue.private` defaults to false, and
-- `venue` has no triggers. So:
--
--   the next person who adds their house as a venue gets private = false, their
--   street address goes straight into the still-public venue.address, and it
--   leaks exactly as before.
--
-- The fix cleaned up history and did nothing about the future. Verified:
--   private_default = false, venue_triggers = 0.
--
-- -----------------------------------------------------------------------------
-- Two triggers, because the client cannot help yet
-- -----------------------------------------------------------------------------
-- Thirteen client files still write `address` / `whatsapp` / `contact_name` onto
-- `venue`, and will until the stage-2 client deploy. Rather than wait for that,
-- these triggers make the database do the right thing with whatever the client
-- writes:
--
--   1. a new venue of the private type starts PRIVATE
--   2. whatever lands in the old columns is mirrored into venue_contact, and
--      then blanked on `venue` if the venue is private
--
-- After stage 2 the second one becomes a no-op (the columns will be gone) and
-- can be dropped with them.
-- =============================================================================

begin;

-- 0 ---------------------------------------------------------------------------
-- Make the type mean what people already use it for.
--
-- Type 4 was "Club Privado", described purely as an exclusive members-only
-- establishment. Every venue actually filed under it is somebody's house —
-- Cami's House, Donde Naty, Capivenue. People bent the nearest available type to
-- mean "a private place", which is the behaviour, so the label should say so.
--
-- That also turns the trigger below from a heuristic into a correct reading: the
-- type now genuinely means "a private address", so defaulting `private` from it
-- is not a guess.
--
-- The description is user-facing copy shown when picking a type, so it states
-- the consequence outright. Someone choosing this should know their address
-- stops being public — an invisible privacy behaviour is a worse privacy
-- behaviour.
update public.venue_type
set name = 'Club / Residencia privada',
    description = 'Un club exclusivo o la casa de alguien: desde un espacio solo para miembros hasta una sala, una terraza o un garaje donde se arma un toque entre conocidos. La dirección exacta y los datos de contacto de estos lugares NO son públicos — solo los ven quienes organizan el toque, quienes confirmaron asistencia y quienes van a tocar.'
where id = 4;

-- 1 ---------------------------------------------------------------------------
-- The type now means "a private address" (see above), so a new venue of that
-- type starts private. INSERT only: an admin who later unsets the flag means it,
-- and should not have it forced back on every save.
--
-- Not a complete answer on its own — a house can also be filed under "Espacio al
-- Aire Libre" (8), whose description already mentions "un patio trasero". The
-- explicit toggle in VenueForm is still needed; this covers the common case.
create or replace function public.venue_default_private()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.venue_type = 4 then
    new.private := true;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_venue_default_private on public.venue;
create trigger trg_venue_default_private
  before insert on public.venue
  for each row execute function public.venue_default_private();

-- 2 ---------------------------------------------------------------------------
-- SECURITY DEFINER: venue_contact is behind RLS that only its venue's admins can
-- write, and at INSERT time the creator is not an admin yet (venue_admin has no
-- row). The trigger has to be able to write regardless.
--
-- Known limitation of this bridge, deliberate: a NULL incoming value does not
-- clear the stored one (coalesce keeps it). That is required, because for a
-- private venue the public columns are always null, so every unrelated edit
-- would otherwise wipe the contact details. Clearing an address on purpose is
-- done against venue_contact directly, which venue admins may do.
create or replace function public.sync_venue_contact()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Depth > 1 means we are inside the blanking UPDATE below, re-entering.
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  if new.address is not null or new.whatsapp is not null or new.contact_name is not null then
    insert into public.venue_contact (venue_id, address, whatsapp, contact_name)
    values (new.id, new.address, new.whatsapp, new.contact_name)
    on conflict (venue_id) do update set
      address      = coalesce(excluded.address, public.venue_contact.address),
      whatsapp     = coalesce(excluded.whatsapp, public.venue_contact.whatsapp),
      contact_name = coalesce(excluded.contact_name, public.venue_contact.contact_name);
  else
    -- Still guarantee a row exists, so the client never has to create one.
    insert into public.venue_contact (venue_id) values (new.id)
    on conflict (venue_id) do nothing;
  end if;

  -- The actual protection: a private venue never keeps these in the public table.
  if new.private
     and (new.address is not null or new.whatsapp is not null or new.contact_name is not null) then
    update public.venue
    set address = null, whatsapp = null, contact_name = null
    where id = new.id;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_sync_venue_contact on public.venue;
create trigger trg_sync_venue_contact
  after insert or update on public.venue
  for each row execute function public.sync_venue_contact();

revoke all on function public.venue_default_private() from public, anon, authenticated;
revoke all on function public.sync_venue_contact() from public, anon, authenticated;

-- Belt and braces: re-run the blanking, in case a private venue picked up a
-- contact value between the first migration and this one.
update public.venue
set address = null, whatsapp = null, contact_name = null
where private = true
  and (address is not null or whatsapp is not null or contact_name is not null);

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql. No type regeneration — no
-- column or signature changed.
--
-- VERIFY by creating a venue of type 4 as a signed-in user and then reading it
-- back AS ANON:
--   the new row must come back private = true with address / whatsapp /
--   contact_name all null, while venue_contact holds the real values and is
--   invisible to anon.
--
-- STILL AHEAD on #113:
--   * client reads venue_contact and shows `area` (13 files); VenueForm gains
--     `area` and an explicit `private` toggle, so the venue type stops being the
--     only way in — a house filed under "Espacio al Aire Libre" needs it
--   * stage 2: drop address / whatsapp / contact_name from `venue`, and this
--     migration's second trigger with them
-- =============================================================================
