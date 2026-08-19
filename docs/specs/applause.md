# Applause — requirement spec

**Status:** Draft · captured 2026-08-12 · roadmap phase: **Showtime** (Phase 3)

## Purpose
Let attendees give a single, lightweight sign of appreciation during a toque —
pointed at a **performer**, a **song**, or the **whole night** — and keep it as
history, *without* pulling attention away from the live music.

## Design principles
1. **Minimal in-event interaction.** An attendee's only in-event action is *one
   clap per target*. No feeds, no chat, no repeated tapping, no realtime clap
   animations. The app should keep people present in the room.
2. **One clap, one meaning.** Applause is a deduped endorsement (one per person
   per target), so tallies are honest — not a mash-the-button counter.
3. **Give it the moment it's felt.** Clapping opens as soon as there's something
   to clap for; you don't wait for a song to finish.

## Targets (three kinds)
| Target | Meaning | Points at |
|---|---|---|
| **Performer** | "you were great tonight" | a `profile` |
| **Song** | "that rendition was great" | a `performance` (setlist slot) |
| **Event** | "what a night" | the `party` |

The applause control appears on all three surfaces. **Counts are kept per target
and NOT merged** — a song's applause is not added to its performers' totals. An
aggregated "career applause" can be computed later (see Deferred).

## When clapping is open (the window)
Applause for a toque is open within a window:
- **opens_at** — when the toque goes live (status → live / event start).
- **closes_at** — event end + a grace period (organizer-adjustable; default:
  through the following day).

Outside the window, tallies are read-only history.

Per-target rule inside the window:
- **Song** — opens the moment the song **starts playing** (live mode marks it
  current) and stays open until the window closes. Immediate appreciation is
  intentional.
- **Performer** — open for the whole window.
- **Event** — open for the whole window.

Song timing depends on live mode's "now playing" pointer. Before/without live
mode, fall back to: songs are clappable once the event is live.

## Who can applaud
**Attendees only** — someone who has RSVP'd / is marked present. Depends on the
RSVP / attendance primitive (roadmap Phase 2).

## Data model
```
applause(
  id             pk,
  created_at     timestamptz default now(),
  party_id       -> party        not null,  -- every clap lives inside an event window
  from_user      -> profile      not null,  -- the applauder (must be an attendee)
  target_type    enum 'event' | 'performer' | 'song',
  performer_id   -> profile      null,      -- set iff target_type = 'performer'
  performance_id -> performance  null,      -- set iff target_type = 'song'
  check  (exactly one target column is set, matching target_type),
  unique (from_user, target_type, performer_id, performance_id)
)
```
Rationale: real foreign keys keep referential integrity (vs a generic
`target_id`); `party_id` is always present so the window + attendee checks are
trivial; the `unique` constraint enforces one-clap-per-target.

## Where it surfaces (reads)
- **Performer profile** — total applause received (performer-target).
- **Song / performance** — applause tally; a "crowd favorite" signal for the setlist.
- **Event recap** — the night's total.

## Rules summary
- Attendee-gated (RSVP).
- Within `[opens_at, closes_at]`; song target additionally requires the song to
  have started playing.
- One endorsement per person per target (unique constraint).
- No realtime/cosmetic applause; the tally simply reflects stored endorsements.

## RLS notes
- **INSERT** — authenticated attendee only; the window must be open; the target
  must belong to this `party`; the `unique` constraint absorbs duplicates.
- **SELECT** — open (public read, consistent with the rest of the app).
- **UPDATE** — none.
- **DELETE** — optional "un-clap" (toggle off); decide later.

## Deferred / later
- **Aggregated "career applause"** — attributing a song's applause to the
  musicians who played it. Computed later; per-target counters stay separate now.
- **Un-clap** (toggle a clap back off) — allow or not.
- **Grace-period default + organizer override** UI.
