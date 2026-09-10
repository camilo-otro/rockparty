# Splitting the drum kit: shells, cymbals, and the parts drummers carry

**Status:** specced, not started · **Issue:** #106 · **Extends:** #95 (event logistics) / #97 (quick-start)

> Decisions taken since the first draft: **hi-hat is its own item** (it carries a
> stand and pedal, which crashes and rides do not), the **`code` column is in
> scope here** rather than deferred, and the snare is **`Redoblante`** for this
> scene. Reflected below.

## The problem

"Batería" is one catalogue row, so a venue ticking it is implicitly claiming a
whole kit. In practice a house kit is almost never whole: the venue provides the
shells and hardware, and the drummer brings cymbals — and often the snare and
the kick pedal too. This is the single most common day-of surprise in the whole
equipment list, and today the app has no way to express it.

The consequence is not a missing feature, it is a **wrong answer**. The party
page currently says "Batería · Del local", the organizer reads that as solved,
and nobody discovers the gap until load-in.

## The catalogue already means "shells" — only the UI disagrees

Worth noticing before designing anything: the eight curated suggestions attached
to `Batería` are Pearl Export, Tama Imperialstar, Yamaha Stage Custom, Ludwig
Accent, Gretsch Catalina, Mapex Tornado, DW Design and Sonor AQ2.

Every one of those is a **shell pack**. They are sold without cymbals. The
catalogue's own curated data already treats "Batería" as shells; the UI is the
only place that implies otherwise. This change makes the model honest rather
than introducing a new idea.

## Why this is easy: the hard parts already exist

This is a **data change, not a schema change**. Three things are already in
place, each of which would otherwise have been the expensive bit:

| Piece | State |
|---|---|
| "A musician brings it" | `requirement_source` already has **`performer`** ("Lo trae un músico"), alongside `venue`, `organizer`, `external`. |
| Two sources for one gig | `party_requirement` is **deliberately not unique** on `(party_id, equipment_id)` — the schema comment says so: *"two amps from two sources are two rows"*. |
| Rendering new rows | All four fetch sites are `select(...).order('id')` with no hardcoded names, and `PartyLogistics` already groups the picker into `<optgroup>`s by `category`. |

So "the venue provides the shells, the drummer brings the cymbals" is *already
expressible* as two rows with different `source` values. The only thing blocking
it is that both halves are one catalogue item.

Migration surface is trivial: **2** `venue_equipment` rows and **1**
`party_requirement` row reference `Batería` today.

## The shape: two tiers

The temptation is to add hi-hat, crash, ride, snare and pedal as five new basic
items. That would be wrong, and #97's spec already says why: *"every switch on
that screen is friction"* — which is exactly why Monitores, Cajas DI, Tarima and
Iluminación were deliberately kept off the standard set. Five drum switches
would take the quick-start from six controls to eleven and undo that decision.

The operational split that matters is **shells vs cymbals vs hi-hat**. A drummer
who brings crashes and rides brings them in one bag, so those stay together —
but the hi-hat does not belong in that bag. It is a cymbal *pair plus a stand
with an integral pedal*, where a crash needs only a boom stand that the venue's
hardware usually already includes. "Do you have a hi-hat?" and "do you have
cymbals?" are genuinely different questions with different answers, and a
venue can easily have the stand but not the cymbals, or neither.

### Tier 1 — the standard set (`is_basic = true`)

Replace one row with three. Net effect on the quick-start: **two extra
switches**, six controls to eight.

| Name | Notes |
|---|---|
| `Batería (sin platillos)` | The existing row 6, renamed. Keeps its id, its 8 suggestions, and both venue rows. |
| `Platillos` | New — crashes and rides, the bag a drummer carries. `default_quantity = 1`: a set, not a count. |
| `Hi-hat` | New. Separate because it needs a stand and pedal, not just a boom arm. |

Eight controls is more than #97 wanted, and that is the accepted cost: all three
sit in the same `batería` category, adjacent and reading as one group, and they
default on so a single "Listo" still works. The alternative is continuing to
give a confidently wrong answer.

`Batería (sin platillos)` reads correctly to a non-drummer organizer without
requiring any vocabulary. The alternative, `Batería (cascos y hardware)`, is
more precise and less legible; **"sin platillos" states the thing the organizer
actually needs to know.**

### Tier 2 — in the catalogue, off by default (`is_basic = false`)

Available in the party page's picker for anyone who wants the detail, costing
the quick-start nothing:

- `Redoblante` — drummers are famously particular about snares; very often
  brought rather than borrowed.
- `Pedal de bombo` — same, and a classic forgotten item.
- `Crash`, `Ride` — for organizers who genuinely need per-cymbal granularity.
  Strictly finer than `Platillos`, used *instead* of it rather than alongside.
  (`Hi-hat` is no longer here — it is Tier 1, above.)

A new `category = 'batería'` puts all of these in their own `<optgroup>`, which
the picker renders with no code change.

## What NOT to do to the existing rows

Both venues with a kit today were claiming cymbals implicitly. **Do not
auto-create `Platillos` rows for them** — that would assert something the venue
never said, and the whole point of this change is to stop the app answering
questions nobody asked it.

Leaving cymbals unclaimed surfaces them as a gap, which is the correct outcome
and matches the reasoning already settled in #97:

> If the venue has no equipment recorded it should show anyway — organizers need
> to know what they need to figure out, and it may be an incentive for venues to
> fill their info.

## Two things this turns up

### The electronic-kit case is real, and already in the data

One of the two venues has `Roland TD11` in its notes. An e-kit has no cymbals to
bring — the pads are integral — so a `Platillos` gap at that venue would be a
**false** gap, exactly the kind of wrong answer this spec exists to remove.

It also has different logistics in the other direction: an acoustic kit needs
overheads and mics, an e-kit needs power and a DI feed.

Two ways out, and this should be decided rather than defaulted:

1. **Do nothing structural.** The quick-start already renders the venue's note
   next to the item, so the organizer sees "Roland TD11" and flips the cymbal
   switch off. One tap, no new concepts. Costs a false default.
2. **Add `Batería electrónica` as its own catalogue item.** Defensible on its
   own merits — genuinely different needs, not a workaround — but it is a third
   drum row and starts down the road of modelling kit types.

Option 1 unless e-kits turn out to be common in the scene.

### The `code` column comes with this change, not after it

`20260909_logistics_basic_set.sql` matches catalogue rows by name, on the stated
grounds that *"these names are the catalogue's stable identity"*. Renaming
`Batería` → `Batería (sin platillos)` falsifies that: re-running that migration
would silently match nothing and quietly stop marking the kit as basic. It
matches **`party_role` by name too** (`'Ingeniero de sonido'`), so both tables
are affected.

Three separate forces now point the same way, which is what settles it:

1. This rename breaks name-as-identity outright.
2. #105 breaks it from the other side — a name with translations cannot be an
   identity either.
3. **`Redoblante` is regional.** It is the right word for this scene, but `caja`
   and `tarola` are current elsewhere. A catalogue whose identity is its
   Colombian display name cannot later serve anywhere else without a rename,
   and a rename is exactly what is unsafe today.

So: add `code text` to `equipment` and `party_role` as part of this work —
nullable, backfilled, then `unique not null` — and repoint the name-matching in
existing migrations at it. Stable, English, snake_case, matching the "English
code, Spanish UI" rule that already governs everything else:

```
drum_kit  cymbals  hihat  snare  kick_pedal
pa  mixer  guitar_amp  bass_amp  mics  monitors  di  keys  stage  lighting
mc  sound_engineer                      -- party_role
```

`venue_type` and `instrument` want the same treatment but are not touched here;
they belong to #105. This ticket fixes the two tables it is about to break.

## Suggestions to add

`equipment_suggestion` is curated per item and new rows need their own lists, in
the same spirit as the existing ones (recognisable, gig-realistic, not
aspirational):

- **Platillos**: Zildjian A / ZBT, Sabian AAX / B8X, Meinl HCS / Classics,
  Paiste PST5, Istanbul Agop
- **Redoblante**: Pearl Sensitone, Tama Starphonic, Ludwig Supraphonic,
  Yamaha Stage Custom, Mapex MPX
- **Pedal de bombo**: DW 2000, Tama Iron Cobra, Pearl Eliminator, Yamaha FP7210,
  Mapex Falcon

## Out of scope

- **Sticks, heads, throne, rug.** Consumables and small hardware. The list is a
  planning tool, not a packing list, and every row costs attention.
- **Per-cymbal quantities on `Platillos`.** "2 crashes" is a conversation
  between drummer and organizer, not a field. The `notes` column already exists
  if someone needs to say it.
- **Modelling which parts belong to which kit.** A parent/child `part_of`
  relationship on `equipment` would be the "proper" model and is not worth it:
  it buys a nicer picker and costs a schema change, a UI rewrite, and a concept
  every organizer has to learn.

## Still open

1. **Two new gaps on every toque, from day one.** `Platillos` and `Hi-hat`
   default on and will be unresolved on most events. That is the intent — the
   gaps are real and currently invisible — but the day this ships, every
   organizer's list grows by two red items with no action taken. Worth a look at
   how the party page reads with that before deciding it is fine.
2. **`Crash` / `Ride` as separate rows.** Probably more granularity than anyone
   will use now that `Hi-hat` is split out, and unused catalogue rows are
   clutter in the picker. Recommend shipping without them and adding only if
   someone asks.
3. **The electronic-kit question** above — do nothing structural, or add
   `Batería electrónica`. Recommend the former until e-kits prove common.
