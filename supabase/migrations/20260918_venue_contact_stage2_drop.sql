-- =============================================================================
-- Migration: stage 2 — the moved columns leave `venue` (#113)
-- Date: 2026-09-18
-- =============================================================================
-- IRREVERSIBLE. This DROPS four columns. It must run AFTER the client deploy
-- that stopped reading them, which shipped 2026-09-16.
--
-- Read the checks below before running it. They were all green at the time of
-- writing; re-run them if any time has passed.
--
-- -----------------------------------------------------------------------------
-- Why it is safe
-- -----------------------------------------------------------------------------
-- 1. NO DATA LOSS. Every value is already mirrored in venue_contact, verified
--    row by row across all 10 venues:
--
--      address_mismatch 0 | whatsapp_mismatch 0 | contact_name_mismatch 0
--      contact_mismatch 0 | venues_without_a_venue_contact_row 0
--
--    (For private venues the `venue` copies are already null — blanked when the
--    privacy migration landed — so the mirror is the ONLY copy. That is the
--    whole point, and it is why the check above is the load-bearing one.)
--
-- 2. NOTHING READS THEM. Checked against the DEPLOYED bundle, not the source:
--    no query names these as venue columns. The two `select('*')` call sites
--    (the venue detail and edit pages) simply receive fewer columns — PostgREST
--    expands `*` server-side, so this cannot 400 the way naming a dropped column
--    would.
--
-- 3. NOTHING IN THE DATABASE DEPENDS ON THEM. No views, no indexes, and of the
--    two functions that mention these words, venue_defaults only matches inside
--    a comment. sync_venue_contact genuinely uses them — and goes with them,
--    below.
--
-- -----------------------------------------------------------------------------
-- The trigger goes too
-- -----------------------------------------------------------------------------
-- sync_venue_contact existed to bridge the gap: it mirrored whatever the OLD
-- client wrote onto `venue` into venue_contact, then blanked it. With the
-- columns gone there is nothing to mirror and nothing to blank, and the current
-- client writes to venue_contact directly. Leaving it would be a trigger that
-- fires on every venue UPDATE to do nothing.
--
-- Dropped in the same transaction as the columns, because it reads them and
-- would fail on the next venue write otherwise.
-- =============================================================================

begin;

-- Re-assert the invariant inside the transaction. If anything is still only on
-- `venue`, this aborts instead of dropping it.
do $$
declare v_bad int;
begin
  select count(*) into v_bad
  from public.venue v
  left join public.venue_contact c on c.venue_id = v.id
  where (v.address      is not null and c.address      is distinct from v.address)
     or (v.whatsapp     is not null and c.whatsapp     is distinct from v.whatsapp)
     or (v.contact_name is not null and c.contact_name is distinct from v.contact_name)
     or (v.contact      is not null and c.contact      is distinct from v.contact)
     or c.venue_id is null;
  if v_bad > 0 then
    raise exception 'Abortado: % local(es) tienen datos que no están en venue_contact. No se borró nada.', v_bad;
  end if;
end $$;

drop trigger if exists trg_sync_venue_contact on public.venue;
drop function if exists public.sync_venue_contact();

alter table public.venue
  drop column if exists address,
  drop column if exists whatsapp,
  drop column if exists contact_name,
  drop column if exists contact;

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and REGENERATE
-- src/lib/database.types.ts — four columns leave the `venue` Row/Insert/Update.
--
-- VERIFY:
--   select column_name from information_schema.columns
--    where table_schema='public' and table_name='venue';
--     -> address / whatsapp / contact_name / contact all gone, `area` and
--        `private` still there
--
--   then load a venue page as its admin: the address, contact and WhatsApp
--   still render, because they come from venue_contact now.
-- =============================================================================
