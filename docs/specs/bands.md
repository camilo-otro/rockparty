# Bands — spec (#40)

Status: **draft spec** (design-spike output). Decisions marked ✅ are settled;
⚠️ items are assumptions to confirm before building.

## Summary

A **band** is a persistent entity: a named group of musicians who can be signed
up to play songs as a unit. Bands live *inside the existing jam model* — they
sign up **per song**, not as a separate "showcase" event format. When a band
takes a song, the band **owns** that song (its lineup plays it; it isn't an open
jam slot) — this is "model (a)". ✅

Key facts (from the idea dump, all ✅):
- A band is a **new entity**; a musician can be in **many bands**.
- A band has one or more **managers** plus regular **members**.
- **Instruments are per-band**: what a member plays is defined *within each band*
  and can be multiple instruments — and can differ from band to band and from
  their global `profile_instrument` list.
- A band signs up to a song via the **suggest-a-song flow** ("sign up as [band]").
- Approval is **band-as-a-unit** (one yes/no for the organizer).
- Bands have a **profile page**.

## Data model (proposed)

New tables (all with RLS; the app is client-only, so RLS is the whole boundary):

```
band
  id           bigint identity pk
  created_at   timestamptz not null default now()
  name         text not null
  created_by   uuid references profile(id)
  bio          text            -- for the profile page
  avatar_url   text            -- Supabase Storage upload; see Avatar handling
  who_can_sign_up  text not null default 'members'   -- 'members' | 'managers'

band_member
  band_id    bigint references band(id) on delete cascade
  user_id    uuid   references profile(id) on delete cascade
  role       band_role not null default 'member'      -- enum: 'manager' | 'member'
  created_at timestamptz not null default now()
  primary key (band_id, user_id)

band_member_instrument                 -- what this member plays IN THIS band
  band_id       bigint
  user_id       uuid
  instrument_id bigint references instrument(id)
  primary key (band_id, user_id, instrument_id)
  foreign key (band_id, user_id) references band_member(band_id, user_id) on delete cascade
```

Linking a band to the songs it plays — extend the existing setlist tables:

```
performance
  + band_id bigint null references band(id)   -- set => this song is owned by a band

performance_user
  + band_id bigint null references band(id)    -- tags the rows created by a band signup
```

- A **band signup** to a song = set `performance.band_id` and create the lineup
  as `performance_user` rows (each member × each of their band-instruments),
  tagged with the same `band_id`, at status `pending`. Approving the band flips
  all those rows to `approved` in one action. The `performance_user` rows are a
  **snapshot** of who played what, so later roster changes don't rewrite history.
- A performance is therefore **either** an open jam (individual `performance_user`
  signups, `band_id` null) **or** band-owned (`performance.band_id` set). One
  band per song; two bands wanting the same song = two setlist entries.

### RLS / RPC note (important)
Signing a band up inserts `performance_user` rows for **other** members, which
the current "insert self" policy forbids. Do this through a **SECURITY DEFINER
RPC** `sign_band_up(performance_id, band_id)` that verifies the caller may sign
up that band (`who_can_sign_up` + role) and inserts the lineup — mirroring the
trigger/RPC pattern already used for notifications. Approval reuses the existing
`performance_user` status flow, acting on all rows sharing `(performance_id,
band_id)`.

Rough policy intent:
- `band`, `band_member`, `band_member_instrument`: **SELECT public** (profiles
  are discoverable). Writes restricted to that band's **managers** (creator is a
  manager). `is_band_manager(band_id)` helper, like the venue-admin checks.
- Roster management in v1 is **manager-driven** (managers add/remove members and
  set their instruments). An invite→accept flow is a later refinement.

## Roles & permissions ✅
- **Manager** — manage the roster, instruments, and band settings; can sign the
  band up.
- **Member** — by default can suggest songs + sign the band up; a band whose
  `who_can_sign_up = 'managers'` restricts signup to managers.
- Creator is the first manager.

## Flows

### 1. Create a band
`/bands/create`: name, (optional bio/avatar), add members and pick **what each
plays in this band** (multi-instrument per member). Creator becomes a manager.

### 2. Sign a band up to a song (primary entry point)
From the existing **suggest-a-song** flow on a toque, the chooser gains
**"just me" vs "as [one of my bands]"**. Picking a band:
- creates the `performance` (song) with `band_id`,
- signs up the band's lineup (`sign_band_up` RPC) at `pending`,
- follows the toque's `performer_approval` mode (auto / organizer / proponent /
  invite_only) for whether it needs approval.

A member suggesting a song sees their bands as options (idea #4). Managers get
**repertoire suggestions** — songs the band has played before — when adding songs
(idea #5; derivable from past `performance.band_id`, so it's free once bands have
history; **v2**).

### 3. Approval — band as a unit ✅
The organizer/approver sees the band as **one item** ("Los Whatever — Voz · Bajo
· Batería · Guitarra") and approves/declines the **whole act**. v1 is
**band-or-nothing** (no per-member approve/drop for a song); member-swap-for-a-song
is a later refinement. Reuses the existing signup notifications.

### 4. Band-owned song on the setlist
A band-owned song shows the **band's lineup**, not open instrument gaps (the
gaps/"te necesitan" UI only applies to open jam songs). Two guitarists etc. are
fine — it's the band's lineup, not one-slot-per-instrument. **Collabs / features**
(idea #6) are the explicit exception: a band-owned song can **open one guest slot**
for a non-member to claim. Mechanic **TBD — v2**; the model already allows it (a
`performance_user` row on a band-owned performance whose `user_id` isn't in
`band_member`).

### 5. Band profile page ✅ (`/bands/[id]`)
- Header: band name, avatar, bio.
- **Roster**: members with their band-instruments; managers marked.
- **Toques**: upcoming toques the band is in + past toques it played (from
  `performance.band_id` → party).
- Manager affordance: **manage band** (edit roster/instruments/settings).
- Discoverable from a member's performer profile ("Toca en: Los Whatever, …")
  and from band-owned setlist rows.

## Touch points (existing features affected)
- **Suggest-song / signup** — the "as a band" chooser + `sign_band_up`.
- **Approval** — group band rows into one approve/decline unit.
- **Setlist rendering** — band-owned rows show the band + lineup, suppress the
  gaps UI.
- **Applause & history** (Phase 3, not built) — applaud the **band/act**, and the
  band profile accrues its history.
- **Performer profile** — list the bands a musician plays in.

## Deferred (design as extensible, don't build in v1)
- **Collabs / features** (idea #6) — the "open a guest slot on a band song".
- **Repertoire suggestions** (idea #5) — derivable; add once bands have history.
- **Invite→accept** roster flow (v1 is manager-adds-members).
- **Per-song member swap** at approval.
- **Showcase / set-based** event format (Scenario B) — not needed for model (a).

## Confirmed decisions (v1)
1. **Roster = managers add members directly** — no invite→accept step in v1. ✅
2. **Approval is band-or-nothing** per song — no per-member drop/swap in v1. ✅
3. Route **`/bands/[id]`**, Spanish UI label **"Bandas"**. ✅
4. Avatar is a **Supabase Storage upload** (free tier), optimized client-side —
   see Avatar handling. ✅

## Avatar handling (band.avatar_url)
Free-tier-first, so keep uploaded images small and cheap:
- A dedicated Storage bucket (e.g. `band-avatars`); RLS so only a band's
  **managers** can write its avatar, public read.
- **Optimize before upload, client-side:** square-crop, downscale to a small max
  (e.g. 512×512), re-encode to WebP/JPEG at moderate quality, and enforce a hard
  size cap (e.g. ≤ ~150 KB) — reject/we-shrink oversized files rather than storing
  originals. A simple square crop-and-resize on a `<canvas>` covers it; no server
  processing needed. Same approach is reusable for venue/performer avatars later.
- Store only the resulting object URL in `band.avatar_url`.

## Build breakdown (tickets)
Epic: **#40**. v1 tickets (dependency order):
1. **#70** — data model + RLS foundation (tables, `band_id` columns, helpers,
   `sign_band_up` RPC). *Blocks the rest.*
2. **#71** — create & manage a band (`/bands/create`, roster, per-band instruments).
3. **#72** — profile page (`/bands/[id]`) + performer-profile links.
4. **#73** — sign up as a band (suggest-song "as [band]" + RPC).
5. **#74** — approval-as-a-unit + band-owned setlist rendering.
6. **#75** — avatar upload (Storage + client optimize/crop/limit).

Deferred (own tickets when picked up): collabs/features, repertoire suggestions,
invite→accept, per-song member swap.
