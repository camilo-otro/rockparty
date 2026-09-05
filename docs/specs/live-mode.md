# Live mode — build spec

**Status:** Ready to build · drafted 2026-08-12, resolved 2026-09-05 · roadmap phase: **Showtime** (Phase 3) · issue #37

**Target:** usable on **19 Sep 2026** — "Amistad y Amor por el Rock", 10 songs
across 4 bands. That date drives the staging below: Stage 1 is what has to work
on the night; Stages 2–3 are the rest of the spec, shipped after.

## Purpose
During a toque, broadcast the show's progress in real time — **now playing**,
**who's on it**, **what's next** — and give party admins a dead-simple way to
drive it. Live mode is the *engine* the audience view and song applause read.

## The core idea
The show's progress is a single piece of state: **which performance is playing
right now**. Admins move it; everything else derives from it.

## Resolved decisions

The draft left four open. Settled, with reasons:

### 1. No pointer column on `party` — derive it from `performance`
The draft proposed `party.current_performance_id`. Don't. Instead give each
performance a `live_state` and treat the single `playing` row as the pointer.

Why the change:
- **`performance` is already in the `supabase_realtime` publication**
  (`notification, performance, performance_user`); `party` is **not**. Deriving
  from `performance` means the audience view streams with no new plumbing, and
  each song's own row carries its own state.
- It removes the dual source of truth the draft flagged as an open decision — a
  pointer *and* a per-song enum can disagree; one enum can't.

Invariant enforced in the DB, not the client:
```sql
create unique index performance_one_playing_per_party
  on public.performance (party) where live_state = 'playing';
```
Two admins tapping Next at once can then only produce one winner and one
constraint error, instead of two "now playing" songs.

`party` still gets added to the realtime publication so `status` changes
(show started / ended / cancelled mid-show) stream to the audience too.

### 2. Advance is manual — confirmed
No timer moves the show along. The admin taps Next. Matches "augment the humans,
don't automate their judgment": the person on stage decides when a song is over.

### 3. Multi-admin: last-action-wins, no lock
The unique index makes a race safe rather than corrupt. A "show runner" lock is
speculative until we see it hurt — the 19 Sep toque has one person running it.
On a lost race the loser refetches and re-renders; no error toast for a
`23505` on this index, just resync.

### 4. `completed`, not `done`
The draft said "End show — party status → done". **There is no `done`** in
`party_status` — the enum is
`draft | pending_venue | confirmed | live | completed | cancelled`. End show sets
**`completed`**.

Worth knowing: `live` and `completed` have **never been used in production** —
every party to date has only been `draft`, `confirmed` or `cancelled`. Live mode
is the first code to exercise those two transitions, so the status-change
notification trigger (`notify_party_status`) needs checking against them rather
than assumed working.

## Schema

```sql
create type public.performance_live_state as enum
  ('queued', 'playing', 'played', 'skipped');

alter table public.performance
  add column if not exists live_state public.performance_live_state not null default 'queued',
  add column if not exists started_at timestamptz,
  add column if not exists ended_at   timestamptz;

create unique index if not exists performance_one_playing_per_party
  on public.performance (party) where live_state = 'playing';
```

`started_at` is what opens song applause (see `applause.md`) — one Next tap makes
a song live for the room *and* clappable.

**Reset semantics:** ending a show leaves `queued` rows as they are. A song never
played stays `queued`, which reads correctly in history as "didn't get to it".

## Security — already in place
`performance` UPDATE is **already restricted to the party's creator or a
`party_admin`**, so advancing the show is admin-only without new policy work:

```sql
create policy "Enable Update for authenticated users only" on public.performance
  for update to authenticated using ( ...party creator or party_admin... );
```

Two notes:
- **CLAUDE.md is stale here.** It still says "`performance` UPDATE is open to any
  authenticated user (`using true`)". That was tightened; fix the note.
- The policy has no `with check`, so an admin could in principle move a
  performance to another party. Pre-existing, out of scope for #37, worth an
  issue.

`party` UPDATE (for `status`) is already admin-gated the same way.

## Surfaces

### Admin console — `/parties/[id]/live`
Running a live event, possibly on stage, with little attention to spare.
- **One-thumb, low-attention.** A single large **Next** is ~90% of taps.
- **Glanceable.** Big Now Playing card (song, artist, band or lineup), huge Next,
  upcoming queue below, played list collapsed above.
- **Forgiving.** Every action correctable.

Reachable from the detail page for admins once the date is today, or any time for
a test party.

### Audience view
Not a new route — the **existing detail page** grows a Now Playing banner above
the setlist while `party.status = 'live'`, and setlist rows show their state
(playing / played / skipped). Reuses the band-set grouping already shipped.

## Staged plan

### Stage 1 — the night itself (must ship before 19 Sep)
1. Migration: enum, three columns, the partial unique index; add `party` to the
   realtime publication. Reconcile `schema.sql`, regenerate `database.types.ts`.
2. **Start show** — `party.status → 'live'`, cue the first song by running order.
3. **Next** — set current `played` + `ended_at`, next `playing` + `started_at`.
4. **End show** — current `played`, `party.status → 'completed'`.
5. Admin console with Now Playing + Next + upcoming queue.
6. Audience: Now Playing banner on the detail page, live over Realtime.
7. Verify the `notify_party_status` trigger fires sanely on `live` / `completed`
   (never exercised before).

That is a complete, honest show-runner: start, advance through the setlist, end.

### Stage 2 — the messy-reality controls
- **Jump to any song** (tap a queued row) — encores, out-of-order reality.
- **Back / undo** — correct a misfire.
- **Skip** — mark `skipped`, move on.
- **Mark current done** without cueing the next — a break between acts.

### Stage 3 — the rest
- **Add a song on the fly** (reuses the add-to-setlist flow).
- **"Who's running the show"** presence.
- **History**: set times per band from `started_at`/`ended_at`, and "what actually
  got played" — this is what makes the estimated-duration feature retrospective.

## Risks
- **Effort L against 14 days.** Stage 1 is the mitigation; if it slips, the toque
  runs the way it does today and nothing is lost.
- **Untested status transitions** (`live`, `completed`) — see above.
- **Realtime on the free tier** already carries `notification`, `performance`,
  `performance_user`. Adding `party` is small, but live mode means many more
  events per minute during a show. Watch the free-tier concurrent-connection
  ceiling with a room full of phones on the audience view.

## Dependencies
Party status model (Phase 0) · setlist ordering (done) · band-set grouping (done)
· Supabase Realtime (extend publication).
Feeds: `applause.md` (#38) via `started_at` — #38 cannot start until Stage 1 lands.
