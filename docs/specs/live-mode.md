# Live mode — requirement spec

**Status:** Draft · captured 2026-08-12 · roadmap phase: **Showtime** (Phase 3)

## Purpose
During a toque, broadcast the show's progress in real time — **now playing**,
**who's on it**, **what's next** — and give party admins a dead-simple way to
drive that progress. Live mode is the *engine* the audience live view and the
song-applause rule both read from.

## The core idea
The show's progress is a single piece of state: **which performance is now
playing**. Party admins move that pointer through the ordered setlist; everything
else derives from it. "Mark the progress" = "advance the now-playing pointer."

## Admin control surface — "run the show"
The admin is running a live event, possibly on stage, with little attention to
spare. Design constraints:

1. **One-thumb, low-attention.** The primary action is a single large **Next** —
   mark the current song done and start the next. It's ~90% of all taps.
2. **Forgiving — live shows are messy.** Skips, reorders, encores, breaks, an
   unplanned song. Every action is correctable.
3. **Glanceable.** Big Now Playing card, huge Next button, upcoming queue below
   (tap any to jump), played list collapsible above.

Actions:
- **Start show** — party status → live. (Optionally cue the first song.)
- **Next / advance** — mark current *played*, set the next song *playing*. The workhorse.
- **Mark current done** — end the current song without auto-cueing the next (a break between acts).
- **Skip** — mark a song *skipped* and move on.
- **Jump to any song** — set any performance as current (reorder / encore / out-of-order reality).
- **Back / undo** — correct a misfire.
- **Add a song on the fly** — pull an unplanned song into the live setlist (reuses add-to-setlist).
- **End show** — party status → done; starts the applause grace timer (see applause spec).

## State model
- `party.status` — `live` / `done` (from the party status-model keystone, Phase 0).
- `party.current_performance_id` → `performance` — the now-playing pointer; null between songs.
- `performance.started_at`, `performance.ended_at` — timestamptz, nullable.
- `performance` live state: `queued | playing | played | skipped`.

Advancing: set previous song's `ended_at`, next song's `started_at`, move the
pointer. `started_at` is the trigger that opens **song applause** (see
`applause.md`) — so one "Next" tap makes the song live for the room *and*
clappable, together.

## What reads this state
- **Audience live view** (Realtime) — now playing / up next / who's on it.
- **Song applause** — opens when `performance.started_at` is set.
- **History** — started/ended timestamps give set times and "what actually got played."

## Realtime & concurrency
- Broadcast `current_performance_id` (and per-song state) changes over **Supabase
  Realtime**; the audience view subscribes and updates live.
- Multiple party admins may be present. Simplest model: shared pointer,
  **last-action-wins**; optionally surface "who's running the show." (Open decision.)

## Open decisions / assumptions
- **Advance is manual.** The admin taps Next; no auto-timer moves the show along.
  (Assumption — matches "mark the progress." Confirm.)
- **Per-song state: store vs derive.** Keep an explicit `queued|playing|played|
  skipped` enum, or derive it from the pointer + timestamps. Leaning explicit
  enum for clarity + easy queries.
- **Multi-admin concurrency** — last-write-wins vs a soft "show runner" lock.

## Dependencies
- Party status model (Phase 0) · setlist ordering (done) · Supabase Realtime (new infra).
- Feeds: audience live view, `applause.md` (song `started_at` trigger).
