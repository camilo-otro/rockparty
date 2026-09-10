-- =============================================================================
-- Migration: stable codes on the catalogues, and split the drum kit (#106)
-- Date: 2026-09-10
-- =============================================================================
-- Spec: docs/specs/drum-kit-cymbals-split.md
--
-- A venue ticking "Batería" implicitly claims a whole kit. A house kit is almost
-- never whole: the venue provides shells and hardware, the drummer brings
-- cymbals — and often the snare and the kick pedal too. That is not a missing
-- feature, it is a WRONG ANSWER. The party page says "Batería · Del local", the
-- organizer reads it as solved, and nobody finds out until load-in.
--
-- The model already supports the fix. requirement_source has `performer` ("Lo
-- trae un músico"), and party_requirement is deliberately NOT unique on
-- (party_id, equipment_id) — two sources for one gig are already two rows. The
-- only thing blocking "venue brings the shells, drummer brings the cymbals" is
-- that both halves are a single catalogue item. So this is data, not schema.
--
-- Corroboration that the catalogue already meant "shells": every one of the
-- eight curated suggestions on Batería (Pearl Export, Tama Imperialstar, Yamaha
-- Stage Custom, ...) is a SHELL PACK, sold without cymbals. Only the UI implied
-- otherwise.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. `code` — the identity a display name can no longer be
-- ---------------------------------------------------------------------------
-- 20260909_logistics_basic_set.sql matches these catalogues BY NAME, on the
-- stated grounds that "these names are the catalogue's stable identity". The
-- rename below falsifies that, and it is not the only thing doing so. Three
-- independent forces:
--
--   1. This migration renames Batería, so name-matching breaks outright.
--   2. #105 (i18n) breaks it from the other side: a name that has translations
--      cannot be an identity either.
--   3. "Redoblante" is REGIONAL. It is the right word for this scene, but
--      `caja` and `tarola` are current elsewhere, so a catalogue keyed on its
--      Colombian display name could never travel.
--
-- English snake_case, matching the "English code, Spanish UI" rule that already
-- governs routes, tables and enums. Both tables get it because that migration
-- matches both by name ('Micrófonos' AND 'Ingeniero de sonido').
--
-- Three steps rather than one: a NOT NULL UNIQUE column cannot be added to a
-- table that already has rows without a default, and a default here would be a
-- lie (there is no sensible generic code).
alter table public.equipment  add column if not exists code text;
alter table public.party_role add column if not exists code text;

-- Backfill by name — safe precisely because this runs BEFORE the rename below,
-- which is the last moment names are still the identity.
update public.equipment set code = c.code from (values
  ('Sistema de sonido (PA)',   'pa'),
  ('Consola de mezcla',        'mixer'),
  ('Micrófonos',               'mics'),
  ('Monitores',                'monitors'),
  ('Cajas DI',                 'di'),
  ('Batería',                  'drum_kit'),
  ('Amplificador de guitarra', 'guitar_amp'),
  ('Amplificador de bajo',     'bass_amp'),
  ('Teclado/Piano',            'keys'),
  ('Tarima',                   'stage'),
  ('Iluminación',              'lighting')
) as c(name, code) where public.equipment.name = c.name and public.equipment.code is null;

update public.party_role set code = c.code from (values
  ('Presentador (MC)',    'mc'),
  ('Ingeniero de sonido', 'sound_engineer')
) as c(name, code) where public.party_role.name = c.name and public.party_role.code is null;

-- Fail loudly rather than silently leaving a null: if a row was renamed by hand
-- between the seed and now, the constraints below would fail with a much less
-- helpful message.
do $$
declare n int;
begin
  select count(*) into n from public.equipment where code is null;
  if n > 0 then raise exception 'equipment: % row(s) got no code — check for renamed rows', n; end if;
  select count(*) into n from public.party_role where code is null;
  if n > 0 then raise exception 'party_role: % row(s) got no code', n; end if;
end $$;

alter table public.equipment  alter column code set not null;
alter table public.party_role alter column code set not null;

-- Postgres has no `add constraint if not exists`, and everything else in this
-- file is re-runnable (`add column if not exists`, `on conflict do nothing`), so
-- these would be the one pair of statements that fail on a second run. Same
-- duplicate_object pattern the schema already uses for enum types.
do $$ begin
  alter table public.equipment add constraint equipment_code_key unique (code);
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.party_role add constraint party_role_code_key unique (code);
exception when duplicate_object then null; end $$;

-- ---------------------------------------------------------------------------
-- 2. The split
-- ---------------------------------------------------------------------------
-- The existing row is RENAMED, not replaced: it keeps its id, so both
-- venue_equipment rows and the one party_requirement pointing at it stay
-- correct, and it keeps its eight shell-pack suggestions, which were always
-- describing this narrower thing anyway.
--
-- "sin platillos" over the more precise "cascos y hardware": the reader is
-- usually not a drummer, and it states the fact they actually need.
update public.equipment
   set name = 'Batería (sin platillos)',
       category = 'batería'
 where code = 'drum_kit';

-- Hi-hat is deliberately NOT folded into Platillos. A drummer carries crashes
-- and rides in one bag, so those stay together — but a hi-hat is a cymbal PAIR
-- PLUS A STAND WITH AN INTEGRAL PEDAL, where a crash needs only a boom arm the
-- venue's hardware usually already includes. "Do you have a hi-hat?" and "do you
-- have cymbals?" have different answers; a venue can have the stand and not the
-- cymbals, or neither.
--
-- Both are is_basic: they are exactly the things that get forgotten, which is
-- the entire point. This takes the #97 quick-start from seven controls to nine —
-- more than that spec wanted ("every switch on that screen is friction") and the
-- accepted cost of not giving a confidently wrong answer. They sit in the same
-- category so they render adjacent, as one group.
insert into public.equipment (code, name, category, is_basic, default_quantity) values
  ('cymbals',    'Platillos',       'batería', true,  1),
  ('hihat',      'Hi-hat',          'batería', true,  1),
  -- Off the standard set: real needs, but not the floor, and every switch on
  -- the quick-start is friction. One tap away on the party page.
  ('snare',      'Redoblante',      'batería', false, null),
  ('kick_pedal', 'Pedal de bombo',  'batería', false, null)
on conflict (code) do nothing;

-- Crash and Ride as separate rows are deliberately NOT added: with hi-hat split
-- out they are more granularity than anyone is likely to use, and unused
-- catalogue rows are clutter in the picker. Trivial to add if someone asks.

-- ---------------------------------------------------------------------------
-- 3. Suggestions for the new items
-- ---------------------------------------------------------------------------
-- Same spirit as the existing 102: recognisable and gig-realistic, not
-- aspirational. Keyed by code so this block does not re-introduce the very
-- name-matching this migration exists to remove.
insert into public.equipment_suggestion (equipment_id, label)
select e.id, s.label
  from public.equipment e
  join (values
    ('cymbals',    'Zildjian A'),
    ('cymbals',    'Zildjian ZBT'),
    ('cymbals',    'Sabian AAX'),
    ('cymbals',    'Sabian B8X'),
    ('cymbals',    'Meinl HCS'),
    ('cymbals',    'Paiste PST5'),
    ('cymbals',    'Istanbul Agop'),
    ('hihat',      'Zildjian A New Beat'),
    ('hihat',      'Sabian XSR'),
    ('hihat',      'Meinl HCS'),
    ('hihat',      'Paiste PST5'),
    ('snare',      'Pearl Sensitone'),
    ('snare',      'Tama Starphonic'),
    ('snare',      'Ludwig Supraphonic'),
    ('snare',      'Yamaha Stage Custom'),
    ('snare',      'Mapex MPX'),
    ('kick_pedal', 'DW 2000'),
    ('kick_pedal', 'Tama Iron Cobra'),
    ('kick_pedal', 'Pearl Eliminator'),
    ('kick_pedal', 'Yamaha FP7210')
  ) as s(code, label) on s.code = e.code
on conflict do nothing;

commit;

-- =============================================================================
-- DELIBERATELY NOT BACKFILLED.
--
-- Both venues that have a kit were claiming cymbals implicitly. Creating
-- Platillos / Hi-hat rows for them would assert something they never said —
-- which is the exact failure this migration exists to fix. Leaving them
-- unclaimed surfaces a real gap, matching the reasoning already settled in #97:
-- "If the venue has no equipment recorded it should show anyway — organizers
-- need to know what they need to figure out."
--
-- The electronic-kit case is real and already in the data: one venue's kit note
-- reads "Roland TD11". An e-kit has no cymbals to bring, so a Platillos gap
-- there is a FALSE gap. Handled without new structure — the quick-start renders
-- the venue's note beside the item, so the organizer reads "Roland TD11" and
-- flips two switches off. Revisit `Batería electrónica` as its own item only if
-- e-kits prove common.
--
-- After applying: regenerate src/lib/database.types.ts and reconcile
-- supabase/schema.sql.
-- =============================================================================
