-- =============================================================================
-- Migration: seed popular equipment descriptions (#49 follow-up)
-- Date: 2026-08-24
-- =============================================================================
-- The venue equipment editor autocompletes the per-item description from
-- existing venue_equipment.notes values. That pool is empty until venues type
-- things in. This adds a small CURATED catalog of common brand/model options
-- per equipment type (world-readable, like the other lookups) so the
-- autocomplete is useful from day one; VenueForm merges it with real usage.
--
-- Picks are industry-standard live/backline gear (grounded via web search).
-- Purely additive seed data — safe to re-run wouldn't duplicate thanks to the PK.
-- =============================================================================

begin;

create table if not exists public.equipment_suggestion (
  equipment_id bigint not null references public.equipment (id) on delete cascade,
  label        text   not null,
  primary key (equipment_id, label)
);
create index if not exists idx_equipment_suggestion_equipment on public.equipment_suggestion (equipment_id);

alter table public.equipment_suggestion enable row level security;
-- World-readable, like role/instrument/equipment lookups. No write policy
-- (curated via migrations only), so inserts/updates/deletes stay denied.
drop policy if exists "allow select to all users" on public.equipment_suggestion;
create policy "allow select to all users" on public.equipment_suggestion
  for select to anon, authenticated using (true);

insert into public.equipment_suggestion (equipment_id, label) values
  -- 1 · Sistema de sonido (PA)
  (1, 'QSC K12.2'), (1, 'JBL EON715'), (1, 'Yamaha DBR12'), (1, 'RCF ART 912-A'),
  (1, 'Electro-Voice ELX200'), (1, 'Mackie Thump215'), (1, 'Behringer Eurolive B215'), (1, 'Bose L1 Pro'),
  -- 2 · Consola de mezcla
  (2, 'Behringer X32'), (2, 'Behringer XR18'), (2, 'Yamaha MG16XU'), (2, 'Yamaha TF3'),
  (2, 'Allen & Heath SQ-5'), (2, 'Allen & Heath Qu-16'), (2, 'Soundcraft Signature 12'), (2, 'Midas M32'),
  -- 3 · Micrófonos
  (3, 'Shure SM58'), (3, 'Shure SM57'), (3, 'Shure Beta 58A'), (3, 'Sennheiser e935'),
  (3, 'Sennheiser e835'), (3, 'AKG D5'), (3, 'Audix OM2'), (3, 'Behringer XM8500'),
  -- 4 · Monitores
  (4, 'QSC K12.2'), (4, 'Yamaha DBR12'), (4, 'JBL EON712'), (4, 'Behringer Eurolive B112'),
  (4, 'Mackie SRM450'), (4, 'RCF NX 12-SMA'), (4, 'Electro-Voice ZLX-12P'), (4, 'Shure PSM 300 (in-ear)'),
  -- 5 · Cajas DI
  (5, 'Radial ProDI'), (5, 'Radial JDI'), (5, 'Radial J48'), (5, 'BSS AR-133'),
  (5, 'Behringer Ultra-DI DI100'), (5, 'Countryman Type 85'), (5, 'LD Systems LDI02'), (5, 'Whirlwind IMP 2'),
  -- 6 · Batería
  (6, 'Pearl Export'), (6, 'Tama Imperialstar'), (6, 'Yamaha Stage Custom'), (6, 'Ludwig Accent'),
  (6, 'Gretsch Catalina'), (6, 'Mapex Tornado'), (6, 'DW Design'), (6, 'Sonor AQ2'),
  -- 7 · Amplificador de guitarra
  (7, 'Fender Twin Reverb'), (7, 'Fender Hot Rod Deluxe'), (7, 'Marshall JCM800'), (7, 'Marshall DSL40'),
  (7, 'Vox AC30'), (7, 'Roland JC-120'), (7, 'Orange Rockerverb'), (7, 'Peavey Classic 30'),
  -- 8 · Amplificador de bajo
  (8, 'Ampeg SVT'), (8, 'Ampeg BA-115'), (8, 'Fender Rumble 500'), (8, 'Gallien-Krueger MB Series'),
  (8, 'Markbass Little Mark'), (8, 'Hartke HD Series'), (8, 'Trace Elliot ELF'), (8, 'Aguilar Tone Hammer'),
  -- 9 · Teclado/Piano
  (9, 'Yamaha P-125'), (9, 'Nord Stage 3'), (9, 'Roland RD-2000'), (9, 'Korg Kronos'),
  (9, 'Yamaha MODX'), (9, 'Nord Electro 6'), (9, 'Casio Privia PX'), (9, 'Roland Juno-DS'),
  -- 10 · Tarima (descriptivo — tamaño/altura)
  (10, 'Tarima 2x1 m'), (10, 'Practicables 1x2 m'), (10, 'Altura 20 cm'), (10, 'Altura 40 cm'),
  (10, 'Altura 60 cm'), (10, 'Escenario 6x4 m'), (10, 'Tarima modular'), (10, 'Plataforma con faldón'),
  -- 11 · Iluminación
  (11, 'PAR LED'), (11, 'Cabeza móvil'), (11, 'Barra LED'), (11, 'Chauvet DJ'),
  (11, 'American DJ (ADJ)'), (11, 'Máquina de humo'), (11, 'Seguidor (followspot)'), (11, 'Blinder LED'),
  -- Mercado colombiano — marcas económicas/locales comunes en bares y salas de
  -- ensayo (B52 y American Sound dominan el PA de gama baja; Backstage y Lexsen,
  -- los amplis; Soundking, consolas/PA económicos).
  (1, 'B52'), (1, 'American Sound'), (1, 'Soundking'), (1, 'Backstage'), (1, 'Apogee'),  -- PA
  (2, 'Soundking'), (2, 'PreSonus StudioLive'),                                           -- consola
  (4, 'B52'), (4, 'Soundking'),                                                           -- monitores
  (7, 'Backstage'), (7, 'Lexsen'),                                                        -- amp guitarra
  (8, 'Backstage'), (8, 'Lexsen'),                                                        -- amp bajo
  (11, 'Big Dipper')                                                                      -- iluminación
on conflict (equipment_id, label) do nothing;

commit;
