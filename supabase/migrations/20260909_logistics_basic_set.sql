-- =============================================================================
-- Migration: mark the "standard set" in the catalogues (#97)
-- Date: 2026-09-09
-- =============================================================================
-- Spec: docs/specs/logistics-quick-start.md
--
-- #95 built the logistics list; it starts EMPTY, which is why nobody fills it
-- in. #97 offers the standard set in one pass at creation. This migration is the
-- data half: which catalogue entries count as "standard", and how many of each.
--
-- A COLUMN rather than a hardcoded list in the client, so the set can be tuned
-- from the SQL editor without a deploy — the same curated-catalogue treatment
-- equipment_suggestion already gets. Deriving it from `category` was considered
-- and rejected: "sonido + backline, not escenario" is a guess that would be
-- wrong for some venues and could not be corrected.
--
-- Both catalogues are already world-readable, so there are no policy changes
-- here — only columns and seed values.
-- =============================================================================

begin;

alter table public.equipment
  add column if not exists is_basic boolean not null default false;
-- How many a typical toque needs. Null means "one, unspecified" — the UI shows a
-- stepper starting at 1 either way; this is only for items where more than one
-- is the norm.
alter table public.equipment
  add column if not exists default_quantity integer;

-- NOTE: party_role gets is_basic but deliberately NOT default_quantity. The
-- quantity_is_equipment_only check constraint on party_requirement forbids a
-- quantity on a role ("two mics" makes sense; "two MCs" is two rows with two
-- names), so a stepper must never be rendered for one. The database enforces it,
-- so a mistake here surfaces as a 400 rather than silent bad data.
alter table public.party_role
  add column if not exists is_basic boolean not null default false;

-- ---------------------------------------------------------------------------
-- The floor for a rock gig, from the existing 11-item catalogue
-- ---------------------------------------------------------------------------
-- Matched on NAME rather than id: ids are identity-generated and a re-seed could
-- renumber them, whereas these names are the catalogue's stable identity (the
-- same reasoning as youtubeTermFor in the performance page).
update public.equipment set is_basic = true, default_quantity = 1
 where name in ('Sistema de sonido (PA)',
                'Consola de mezcla',
                'Batería',
                'Amplificador de guitarra',
                'Amplificador de bajo');

update public.equipment set is_basic = true, default_quantity = 2
 where name = 'Micrófonos';

-- Monitores, Cajas DI, Tarima and Iluminación stay off the standard set: real
-- needs for some toques, but not the floor, and every switch on that screen is
-- friction. They remain one tap away on the party page.

update public.party_role set is_basic = true
 where name = 'Ingeniero de sonido';

-- Presentador (MC) stays off: plenty of toques have no host, and defaulting one
-- on would put a gap in every organizer's list that most of them do not have.

commit;

-- =============================================================================
-- After applying: regenerate src/lib/database.types.ts and reconcile
-- supabase/schema.sql.
-- =============================================================================
