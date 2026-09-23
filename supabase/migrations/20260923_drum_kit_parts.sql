-- =============================================================================
-- Migration: the drum kit becomes a kit — parts under a parent (#106 follow-up)
-- Date: 2026-09-23
-- =============================================================================
-- ADDITIVE + a data reshape. SAFE TO APPLY BEFORE THE CLIENT DEPLOY: the three
-- new columns are ignored by the old client, and every existing fetch site is
-- `select(...).order('id')` with no hardcoded names, so the old UI simply
-- renders the new rows as three more flat switches. Nothing it reads disappears
-- except `Platillos`, whose rows are repointed rather than dropped (see 4).
--
-- -----------------------------------------------------------------------------
-- What changed since drum-kit-cymbals-split.md
-- -----------------------------------------------------------------------------
-- That spec put "modelling which parts belong to which kit" explicitly OUT of
-- scope: a parent/child relationship "buys a nicer picker and costs a schema
-- change, a UI rewrite, and a concept every organizer has to learn."
--
-- That call is now reversed, deliberately. The reason it was right then and is
-- wrong now: the spec was weighing one extra switch against a schema change. It
-- shipped three drum rows and this change takes it to eight, and eight flat
-- switches in a nine-item list IS the concept every organizer has to learn —
-- just without anything on screen to explain it. A parent that expands costs one
-- idea and hides seven rows until they are asked for; eight siblings cost no
-- ideas and hide nothing. The spec's own principle ("every switch on that screen
-- is friction") is what flips the answer once the row count moves.
--
-- -----------------------------------------------------------------------------
-- The shape
-- -----------------------------------------------------------------------------
--   Batería                       parent, is_basic, shown collapsed
--     Bombo, Redoblante,          default_on — what a house kit actually has
--     Hi-hat, Toms
--     Crash, Ride,                NOT default_on — what the drummer usually brings
--     Pedal de bombo
--
-- `default_on` rather than reusing `is_basic`: they answer different questions.
-- `is_basic` means "offer this in the quick-start at all" and stays FALSE for
-- every part, so a client that knows nothing about parts shows exactly the
-- standard set it always did. `default_on` means "pre-ticked once the parent is
-- on", which only has meaning for a part.
-- =============================================================================

begin;

-- 1 --- structure -------------------------------------------------------------
alter table public.equipment
  add column if not exists part_of bigint references public.equipment (id) on delete cascade,
  add column if not exists default_on boolean not null default true,
  add column if not exists sort_order integer;

comment on column public.equipment.part_of is
  'Parent item this is a part of (drum kit -> snare, ride, ...). NULL = a top-level item. Parts are hidden until the parent is selected.';
comment on column public.equipment.default_on is
  'For a part: pre-ticked when the parent is switched on. Meaningless for a top-level item, where is_basic decides.';
comment on column public.equipment.sort_order is
  'Display order. Backfilled as id*10 so existing order is preserved exactly, leaving gaps for parts to slot under their parent.';

-- Existing order was `order by id` everywhere; id*10 reproduces it exactly and
-- leaves nine slots between each pair for parts to sit in.
update public.equipment set sort_order = id * 10 where sort_order is null;

-- 2 --- the parent ------------------------------------------------------------
-- "(sin platillos)" was load-bearing while cymbals were invisible. Now that the
-- parts are listed underneath, the qualifier contradicts what is on screen.
update public.equipment
   set name = 'Batería', sort_order = 60
 where code = 'drum_kit';

-- 3 --- existing parts move under it ------------------------------------------
-- Matched on `code`, never on name — #106's whole point.
update public.equipment set part_of = (select id from public.equipment where code = 'drum_kit'),
                            is_basic = false, default_on = true,  sort_order = 62 where code = 'snare';
update public.equipment set part_of = (select id from public.equipment where code = 'drum_kit'),
                            is_basic = false, default_on = true,  sort_order = 63 where code = 'hihat';
update public.equipment set part_of = (select id from public.equipment where code = 'drum_kit'),
                            is_basic = false, default_on = false, sort_order = 67 where code = 'kick_pedal';

-- 4 --- the new parts ---------------------------------------------------------
-- Bombo and Toms did not exist: the shell pack was one row, so "the venue has a
-- kit but the kick head is shot" had nowhere to live.
--
-- !! BUG, fixed by 20260923_drum_kit_parts_fix.sql — APPLY THAT TOO. This
-- column list omits `part_of`, so all four land as top-level items instead of
-- parts of the kit. Left as-run rather than corrected in place, because this
-- file has already been applied and editing it would give a later reader a
-- different database than the one it actually produced.
insert into public.equipment (code, name, category, is_basic, default_on, default_quantity, sort_order)
values
  ('kick',  'Bombo',  'batería', false, true,  1, 61),
  ('toms',  'Toms',   'batería', false, true,  1, 64),
  ('crash', 'Crash',  'batería', false, false, 1, 65),
  ('ride',  'Ride',   'batería', false, false, 1, 66)
on conflict (code) do nothing;

-- 5 --- Platillos splits into Crash + Ride ------------------------------------
-- `Platillos` is plural: a venue that ticked it was claiming the pair, so one
-- row becoming two is faithful rather than inventive. Every suggestion attached
-- to it (Zildjian A, Sabian AAX, Meinl HCS, Paiste PST5, Istanbul Agop, ...) is
-- a brand LINE sold as both a crash and a ride, so they copy to each unchanged.
--
-- Done as insert-then-delete rather than two UPDATEs because one row has to
-- become two, and the PKs (venue_id, equipment_id) / (equipment_id, label)
-- would collide on the second.

-- 5a. venue claims
insert into public.venue_equipment (venue_id, equipment_id, quantity, notes)
select ve.venue_id, tgt.id, ve.quantity, ve.notes
from public.venue_equipment ve
cross join lateral (select id from public.equipment where code in ('crash','ride')) tgt
where ve.equipment_id = (select id from public.equipment where code = 'cymbals')
on conflict (venue_id, equipment_id) do nothing;

-- 5b. party requirements — every column carries over, including who is bringing
--     it and whether they confirmed. Splitting a confirmed row keeps both halves
--     confirmed: the person who said "I'm bringing the cymbals" meant both.
insert into public.party_requirement
  (party_id, kind, equipment_id, role_id, quantity, source, assigned_user, assigned_label, notes, confirmed_at, checked_at)
select pr.party_id, pr.kind, tgt.id, pr.role_id, pr.quantity, pr.source,
       pr.assigned_user, pr.assigned_label, pr.notes, pr.confirmed_at, pr.checked_at
from public.party_requirement pr
cross join lateral (select id from public.equipment where code in ('crash','ride')) tgt
where pr.equipment_id = (select id from public.equipment where code = 'cymbals');

-- 5c. curated suggestions
insert into public.equipment_suggestion (equipment_id, label)
select tgt.id, s.label
from public.equipment_suggestion s
cross join lateral (select id from public.equipment where code in ('crash','ride')) tgt
where s.equipment_id = (select id from public.equipment where code = 'cymbals')
on conflict (equipment_id, label) do nothing;

-- 5d. the originals go only after their replacements exist. equipment_suggestion
--     cascades from the equipment delete; venue_equipment and party_requirement
--     are plain FKs, so if 5a/5b had failed to copy a row the final delete would
--     raise a foreign-key violation and abort the whole transaction rather than
--     quietly dropping a venue's claim. That is the intended failure mode.
delete from public.party_requirement
 where equipment_id = (select id from public.equipment where code = 'cymbals');
delete from public.venue_equipment
 where equipment_id = (select id from public.equipment where code = 'cymbals');
delete from public.equipment where code = 'cymbals';

-- 6 --- suggestions for the genuinely new parts -------------------------------
-- Sizes, not just brands: a crash and a ride from the same line differ only by
-- diameter, and that is the thing an organizer needs to read back.
insert into public.equipment_suggestion (equipment_id, label)
select e.id, v.label from public.equipment e
join (values
  ('kick',  'Pearl Export 22"'),      ('kick',  'Tama Imperialstar 22"'),
  ('kick',  'Yamaha Stage Custom 20"'),('kick', 'Mapex Tornado 22"'),
  ('toms',  'Rack 12" + piso 16"'),   ('toms',  'Rack 10" + 12" + piso 16"'),
  ('toms',  'Rack 13" + piso 16"'),
  ('crash', 'Zildjian A 16"'),        ('crash', 'Sabian AAX 16"'),
  ('crash', 'Meinl HCS 16"'),         ('crash', 'Paiste PST5 18"'),
  ('ride',  'Zildjian A 20"'),        ('ride',  'Sabian AAX 20"'),
  ('ride',  'Meinl HCS 20"'),         ('ride',  'Paiste PST5 20"')
) as v(code, label) on v.code = e.code
on conflict (equipment_id, label) do nothing;

-- 7 --- lock it down ----------------------------------------------------------
alter table public.equipment alter column sort_order set not null;

-- A part cannot be a part of a part: the UI renders exactly two levels, and a
-- third would silently disappear from every picker rather than fail visibly.
alter table public.equipment drop constraint if exists equipment_parts_are_flat;
alter table public.equipment add constraint equipment_parts_are_flat check (
  part_of is null or part_of <> id
);

commit;

-- =============================================================================
-- After applying: reconcile supabase/schema.sql and regenerate
-- src/lib/database.types.ts (equipment gains part_of, default_on, sort_order).
--
-- VERIFY:
--   select code, name, part_of, default_on, sort_order from equipment
--    where category = 'batería' order by sort_order;
--     -> drum_kit(60) then kick 61, snare 62, hihat 63, toms 64,
--        crash 65, ride 66, kick_pedal 67 — all part_of = drum_kit's id,
--        default_on true for the first four, false for the last three
--   select * from equipment where code = 'cymbals';          -> zero rows
--   select count(*) from venue_equipment ve join equipment e on e.id=ve.equipment_id
--    where e.code in ('crash','ride');                       -> 2 (was 1 Platillos)
--   select count(*) from party_requirement pr join equipment e on e.id=pr.equipment_id
--    where e.code in ('crash','ride');                       -> 6 (was 3 Platillos)
--
-- and over REST as an anonymous caller, since equipment is world-readable:
--   /equipment?select=code,name,part_of,default_on&order=sort_order
-- =============================================================================
