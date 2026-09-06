# Applause — build spec

**Status:** Ready to build · drafted 2026-08-12, resolved 2026-09-05 · roadmap phase: **Showtime** (Phase 3) · issue #38

**Unblocked by live mode Stage 1**: `performance.started_at` is now written when a
song starts, which is the trigger this spec was waiting on.

## Purpose
Let attendees give a single, lightweight sign of appreciation during a toque —
pointed at a **performer**, a **song**, a **performer on a song**, or the
**whole night** — and keep it as
history, *without* pulling attention away from the live music.

## Design principles (unchanged)
1. **Minimal in-event interaction.** One clap per target. No feeds, no chat, no
   repeated tapping, no realtime clap animations. Keep people present in the room.
2. **One clap, one meaning.** A deduped endorsement, so tallies are honest — not
   a mash-the-button counter.
3. **Give it the moment it's felt.** Clapping opens as soon as there's something
   to clap for; you don't wait for a song to finish.

## Targets
| Target | Meaning | Points at |
|---|---|---|
| **Performer** | "you were great tonight" | a `profile`, **scoped to this toque** |
| **Song&nbsp;performer** | "you nailed *that one*" — the solo, the vocal | a `profile` **on a specific** `performance` |
| **Song** | "that rendition was great" | a `performance` (setlist slot) |
| **Event** | "what a night" | the `party` |

Counts are kept per target and **not merged** — a song's applause is not added to
its performers' totals, and neither is added to the per-night performer total.
Aggregated "career applause" stays deferred.

**Performer and song-performer both stay.** They overlap but say different things
("great all night" vs "great on that one") and they surface in places that
already exist — the MÚSICOS list on the detail page, and the setlist rows. The
alternative considered was dropping the per-night target and summing song-level
claps into a night total; rejected because that quietly rewards whoever played
the most songs.

## Resolved decisions

The draft left four open, and reviewing its data model against Postgres turned up
two defects. All six settled below.

### 1. The draft's `unique` constraint does not actually dedupe — fixed
The draft proposed:

    unique (from_user, target_type, performer_id, performance_id)

In Postgres, **NULLs are distinct in a unique index by default**. For an event
clap both target columns are NULL, so `(me, 'event', NULL, NULL)` can be inserted
any number of times — the exact mash-the-button behaviour principle 2 forbids.
The same hole applies to performer claps (`performance_id` NULL) and song claps
(`performer_id` NULL).

Use partial unique indexes instead — one per target type — clearer than `nulls not distinct`
(available on this project's PG 17.6, but silent about intent):

    create unique index applause_one_event_per_user
      on public.applause (from_user, party_id)      where target_type = 'event';
    create unique index applause_one_performer_per_user
      on public.applause (from_user, party_id, performer_id) where target_type = 'performer';
    create unique index applause_one_song_per_user
      on public.applause (from_user, performance_id) where target_type = 'song';
    create unique index applause_one_song_performer_per_user
      on public.applause (from_user, performance_id, performer_id) where target_type = 'song_performer';

`song_performer` needs no `party_id` in its key — `performance_id` already pins
the toque.

**Add the fourth value now, not later.** `ALTER TYPE ... ADD VALUE` cannot have
the new value *used* in the same transaction that adds it, so retrofitting means
splitting a migration around that. Since #38 is unbuilt, it costs nothing here.

### 2. Performer applause is per-toque, not per-lifetime — fixed
The draft's unique key omitted `party_id` for the performer target, which would
have meant you can clap a given musician **once ever**, not once per night. The
target means "you were great *tonight*", so `party_id` belongs in the key (above).

### 3. The window must not depend on someone remembering to tap "End show"
The draft derived `closes_at` from event end. If an organizer forgets to end the
show — likely, at 2am — the status stays `live` and the window never closes.

Derive it from the date instead, which always exists:

- **opens** when `party.status` is `live` or `completed`
- **closes** at `party.date + 2 days` (i.e. through the end of the following day)

Same rule, no new column, and it survives a show that was never formally ended.
An organizer-adjustable grace period stays deferred.

Per-target rule inside the window:

- **Song** and **song-performer** — additionally require
  `performance.started_at is not null`. That is live mode's now-playing pointer
  having reached it; immediate appreciation is intentional.
- **Performer / Event** — open for the whole window.

### 4. Attendee-gating on RSVP alone would ship a dead feature
The draft says attendees only, meaning a `party_rsvp` row. **There is exactly one
RSVP row in the entire production database.** Gate on that and essentially nobody
at the 19 Sep toque can clap.

Widen "was there" to any of:

- an RSVP row for this party, **or**
- an approved `performance_user` row on one of its songs (you played), **or**
- a party admin (you ran it)

Still meaningfully gated — a random signed-in stranger cannot clap a show they had
nothing to do with — without depending on a primitive nobody uses. Prompting RSVP
harder is a separate question; this shouldn't block on it.

### 5. Un-clap: allowed
A mis-tap should be correctable, consistent with how live mode treats every
action. DELETE your own row; the partial unique index means re-clapping is clean.
This is not engagement-farming — it can only reduce a tally.

### 6. No realtime on applause
The tally reflects stored rows and refreshes on load. `applause` deliberately does
**not** join the realtime publication: a room full of phones clapping would be the
noisiest possible table, for a number nobody watches tick. Principle 1.

## Data model

    create type public.applause_target as enum
      ('event', 'performer', 'song', 'song_performer');

    create table public.applause (
      id             bigint generated by default as identity primary key,
      created_at     timestamptz not null default now(),
      party_id       bigint not null references public.party (id) on delete cascade,
      from_user      uuid   not null references public.profile (id) on delete cascade,
      target_type    public.applause_target not null,
      performer_id   uuid   references public.profile (id) on delete cascade,
      performance_id bigint references public.performance (id) on delete cascade,
      -- the target columns set must match target_type
      constraint applause_target_shape check (
        (target_type = 'event'          and performer_id is null     and performance_id is null) or
        (target_type = 'performer'      and performer_id is not null and performance_id is null) or
        (target_type = 'song'           and performer_id is null     and performance_id is not null) or
        (target_type = 'song_performer' and performer_id is not null and performance_id is not null)
      )
    );

Plus the four partial unique indexes above, and lookup indexes on
`(party_id, target_type)`, `(performance_id)`, `(performer_id)`.

Real foreign keys rather than a generic `target_id`, so referential integrity is
the database's job. `party_id` is always present, which makes the window and
"was there" checks cheap.

## Security

RLS is the whole boundary, as everywhere in this app. The interesting one is
INSERT, which has to enforce four things at once, so it leans on a helper:

    -- SECURITY DEFINER: reads party_rsvp / performance_user without RLS recursion.
    create function public.can_applaud(p_party bigint) returns boolean ...
    --   party.status in ('live','completed')
    --   and now() < party.date + interval '2 days'
    --   and (rsvp row  or  approved performer  or  party admin)

- **INSERT** — `from_user = auth.uid()` **and** `public.can_applaud(party_id)`
  **and** the target belongs to this party:
  - song → `performance.party = party_id and performance.started_at is not null`
  - performer → that profile has an approved `performance_user` row on this party
    (so you cannot clap someone who did not play)
  - song_performer → that profile has an approved `performance_user` row **on that
    performance**, and the performance has started. A tighter check than the
    party-wide performer target, and it falls out of the same table.
- **SELECT** — public, consistent with the rest of the app.
- **UPDATE** — none. A clap is not editable; it is inserted or deleted.
- **DELETE** — `from_user = auth.uid()` only (un-clap).

The target checks are what stop a crafted request clapping a song from another
toque, or a profile who was not on stage. UI hiding is not security here.

## Staging

### Stage A — the night
1. Migration: enum, table, check constraint, three partial unique indexes,
   `can_applaud`, RLS policies. Reconcile `schema.sql`, regenerate types.
2. **Song applause** on the setlist row and the now-playing banner, live and after.
3. **Event applause** once on the detail page.
4. Tallies read from stored rows; no realtime.

### Stage B — people
5. **Performer applause** on the musician rows of a toque (the MÚSICOS list).
6. **Song-performer applause** — the solo, the vocal, the one that landed.

   The schema half is trivial; the interaction is the real cost, and it fights
   principle 1. Four clap buttons inline on every setlist row is exactly the
   attention-sink this spec exists to avoid. So: keep the row itself to one
   control (the song clap), and put per-musician claps **behind a tap** on the
   row, revealing that song's lineup. The data is already loaded —
   `performance_user` is the per-song lineup, and band songs resolve
   `bandLineup` — so this is presentation, not fetching.

   Worth testing on a phone in a dark room before it ships; if it turns out
   fiddly mid-song, it still works fine after the fact, inside the window.
7. Totals on the performer profile (per-toque and lifetime sum), kept separate
   per target type.

### Stage C — the recap
8. Event recap: the night's totals, crowd-favourite song, alongside the Stage 3
   live-mode history (set times, what actually got played).

## Deferred
- Aggregated "career applause" attributing a song's claps to its musicians.
- Organizer-adjustable grace period + its UI.
- Any realtime or animated applause.

## Dependencies
Live mode Stage 1 (`performance.started_at`) — **done** · party status model ·
`party_rsvp` (exists, barely used — see decision 4).
