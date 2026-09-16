-- =============================================================================
-- Migration: venue.contact is a phone number too (#113)
-- Date: 2026-09-16
-- =============================================================================
-- SAFE TO APPLY NOW. Same shape as 20260916_venue_contact_privacy: copy across,
-- blank on private venues, leave the old column in place for the current client.
--
-- -----------------------------------------------------------------------------
-- What I missed
-- -----------------------------------------------------------------------------
-- The first pass moved address / whatsapp / contact_name and left `venue.contact`
-- alone, on the strength of its schema comment: "free-form handle, e.g.
-- @acturo". The data says otherwise. Read as an anonymous caller AFTER that fix:
--
--   <home venue>   contact = <a bare 10-digit mobile number>
--   <home venue>   contact = <an instagram handle>
--   <home venue>   contact = <an instagram handle, someone else's>
--
-- Values redacted; the repo is public.
--
-- The form's own label is "Info de contacto — telefono, correo, instagram", so
-- a phone number there is the field working as designed, not misuse. It belongs
-- on the same side of the line as whatsapp.
--
-- A reminder that "which columns are sensitive" is a question about the DATA,
-- not about what the column was named or commented for.
--
-- `instagram` is deliberately NOT moved. A handle is something people publish on
-- purpose, and the venue page links it as a way to be found. Worth revisiting if
-- that turns out to be wrong for a private home.
-- =============================================================================

begin;

alter table public.venue_contact add column if not exists contact text;

update public.venue_contact c
set contact = v.contact
from public.venue v
where v.id = c.venue_id and c.contact is null and v.contact is not null;

-- Extend the bridge trigger to carry `contact` across as well, so a venue saved
-- by the CURRENT client (which still writes venue.contact) keeps working and
-- still ends up private. Unchanged otherwise — see
-- 20260916_venue_privacy_self_sustaining.sql for why the nulls are coalesced.
create or replace function public.sync_venue_contact()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if pg_trigger_depth() > 1 then
    return null;
  end if;

  if new.address is not null or new.whatsapp is not null
     or new.contact_name is not null or new.contact is not null then
    insert into public.venue_contact (venue_id, address, whatsapp, contact_name, contact)
    values (new.id, new.address, new.whatsapp, new.contact_name, new.contact)
    on conflict (venue_id) do update set
      address      = coalesce(excluded.address, public.venue_contact.address),
      whatsapp     = coalesce(excluded.whatsapp, public.venue_contact.whatsapp),
      contact_name = coalesce(excluded.contact_name, public.venue_contact.contact_name),
      contact      = coalesce(excluded.contact, public.venue_contact.contact);
  else
    insert into public.venue_contact (venue_id) values (new.id)
    on conflict (venue_id) do nothing;
  end if;

  if new.private
     and (new.address is not null or new.whatsapp is not null
          or new.contact_name is not null or new.contact is not null) then
    update public.venue
    set address = null, whatsapp = null, contact_name = null, contact = null
    where id = new.id;
  end if;

  return null;
end;
$$;

revoke all on function public.sync_venue_contact() from public, anon, authenticated;

-- Close it now, as before.
update public.venue set contact = null where private = true and contact is not null;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (one new column on venue_contact).
--
-- VERIFY as an ANONYMOUS caller:
--   /venue?select=name,contact&private=eq.true  -> contact null on every row
--
-- Stage 2 now drops FOUR columns from `venue`: address, whatsapp, contact_name
-- and contact.
-- =============================================================================
