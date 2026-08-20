# Venue profile — requirement spec

**Status:** Draft · captured 2026-08-12 · roadmap phase: **Doors** (Phase 1)

## Purpose
Make a venue a real, decision-useful entity instead of just a name + address:
what gear it has, how the deal works, what the house rules are, and whether
hosting a toque there needs its sign-off. Structured enough to filter on later,
freeform for everything that varies too much.

## What we track (beyond today's name / address / contact / type / allow-flags)

### 1. Equipment & backline  — *structured (filterable)*
- A curated `equipment` lookup + a `venue_equipment` junction — same pattern as
  `instrument` / `performance_user`.
- Seed list: PA system, mixing desk, microphones, monitors, drum kit, guitar amp,
  bass amp, keyboard/piano, DI boxes, stage, lighting.
- Plus a per-venue free-text note for specifics ("2× guitar combos, 1× bass head").

### 2. Engagement model & fees  — *enum + freeform*
- `engagement_model` enum: `free | door_split | guarantee | pay_to_play | tips | bar_minimum | other`.
- `engagement_notes` text — cover amount, split %, minimums, specifics.
- Why it matters: this is what tells a musician *whether and how they get paid*.

### 3. Restrictions & house rules  — *structured where it filters, else freeform*
- Structured: `min_age` (0 = all ages), `curfew` (music-off time), `capacity`.
- Freeform: `house_rules` text — genre limits, covers-only, load-in, smoking, etc.

### 4. Hosting approval  — *feeds the status model*
- `requires_approval` boolean (default **true**).
- Drives a new toque's status path:
  - requires approval → `draft → pending_venue → confirmed` (venue admin approves)
  - doesn't → `draft → confirmed` directly
- **Exception:** if the organizer is already a venue admin of that venue, skip
  `pending_venue` — they are the house.

## Data model
Additions to `venue`:
`requires_approval bool default true`, `engagement_model enum null`,
`engagement_notes text null`, `min_age smallint null`, `curfew time null`,
`capacity int null`, `house_rules text null`.

New tables:
```
equipment(id pk, name text, category text null)
venue_equipment(
  venue_id     -> venue,
  equipment_id -> equipment,
  notes        text null,
  primary key (venue_id, equipment_id)
)
```

## Surfaces
- **Venue detail** — gear chips, engagement model + terms, age / curfew / capacity,
  house rules (alongside today's contact, type, allow-flags).
- **Venue create / edit** — a section per bucket + the approval toggle.
- **Party create** — reads `venue.requires_approval` to set the new toque's
  initial status path (see `party-status.md`).
- **Discovery (later)** — "has a drum kit", "all-ages", "pays" filters, powered by
  the structured fields.

## Permissions (RLS)
- **Venue fields** — edited by venue admins; the existing `venue` UPDATE policy
  (`created_by OR venue_admin`) already covers this. No change.
- **`venue_equipment`** — SELECT public; INSERT/DELETE by venue admins (new
  policies, mirroring the venue ownership check).
- All venue metadata is public (SELECT open), consistent with current venue read.

## Open decisions
- **One engagement model + notes** vs multiple per venue. Recommend one + notes.
- **Restrictions** — structured fields + freeform now, vs a full restriction-tag
  taxonomy. Recommend the former; add tags only if filtering demands it.
- **`requires_approval` default** — true (venue opts into auto) vs false. Recommend true.
- **Equipment taxonomy** — curated lookup vs venue free-add. Recommend curated
  (keeps it filterable) + the "other" note field for specifics.

## Dependencies / feeds
- **Feeds:** party status (`pending_venue`), venue approval flow, discovery /
  filtering, and a musician's decision to play.
- **Uses:** existing venue UPDATE RLS; adds `venue_equipment` + its policies.
