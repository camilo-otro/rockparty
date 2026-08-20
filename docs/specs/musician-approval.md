# Musician approval mode — requirement spec

**Status:** Draft · captured 2026-08-20 · roadmap phase: **Doors** (Phase 1)

## Purpose
Let an organizer decide how musicians who sign up to play get onto a song —
from fully open to curated. It's the performer-side mirror of the venue-approval
flow: the venue approves the *event*; here we decide who approves the *players*.

## The setting — "who approves"
`party.performer_approval` enum, **default `auto`**:

| Mode | Who lets a performer onto a song | For |
|---|---|---|
| `auto` | nobody — sign up and you're on | open jams (default, = today's behavior) |
| `organizer` | party owner / admins | curated events |
| `proponent` | the song's `suggested_by` performer (falls back to the organizer if null) | "it's my song, I pick who joins" |
| `invite_only` | no open signups — an organizer/proponent adds people directly | tight, pre-arranged lineups |

Authority rule: **party admins are always super-approvers.** `proponent` mode
*additionally* delegates per-song approval to that song's proponent. Default is
`auto` (most jams want open signups); asymmetric with `venue.requires_approval`
(default true) on purpose — venue approval protects the venue, performer
approval is opt-in curation. Toque-level; a venue default can be inherited later.

## Signup lifecycle
`performance_user` gains `status`: `pending | approved | declined`.
- **auto** — approved immediately (backward-compatible).
- **organizer / proponent** — lands `pending`; the relevant approver accepts/declines.
- **invite_only** — no public self-signup; rows are created already-approved by the approver.
- **Admin / proponent exception** — if the person signing up is a party admin (or,
  in proponent mode, the song's proponent), they're auto-approved.
- `declined` is terminal for that signup; the performer can withdraw (delete their
  own row) and re-request.

Approval grain = one `performance_user` row (this person, this instrument, this
song). Approvers get a batch-approvable queue.

## Status is server-enforced (the crux)
`status` is **not client-writable**. A trigger owns it (same pattern as
`auto_add_admin`):
- **BEFORE INSERT** — set `status`: `approved` if the inserter is a party admin,
  or the song's proponent, or mode is `auto`; otherwise `pending`. Also **reject a
  self-signup when mode is `invite_only`** and the inserter isn't an admin/proponent.
  Any client-supplied status is ignored.
- **BEFORE UPDATE** — reject a `status` change unless `auth.uid()` is a party admin,
  or (in `proponent` mode) the proponent of that row's song.

## RLS changes
- **INSERT** — tighten from today's `with check (true)` (anyone can sign up *anyone*)
  to `user_id = (select auth.uid())` **OR** party admin **OR** (proponent mode) the
  song's proponent. The `invite_only` guard lives in the trigger. (This INSERT
  tightening is a real fix regardless of the feature.)
- **UPDATE** — own-user (edit own row; trigger still blocks self status change) plus
  party admin, plus (proponent mode) the song's proponent.
- **DELETE** — own-user (withdraw), party admin, or (proponent mode) the song's proponent.
- **SELECT** — `approved` is public; `pending`/`declined` visible only to the row's
  `user_id`, party admins, and (proponent mode) the song's proponent. Mirrors the
  draft-visibility narrowing in `party-status.md`.

## What "approved" gates
Approved signups count as *on stage*: public "who's playing", live mode's "who's on
it", applause participants, and a filled gap. Pending ones surface to the approver
as a queue.

## Handling oversubscription (more applicants than room)
Solve it with **capacity, not judgement**: a song declares the roles it needs and
how many — `needs: 1 drums · 1 bass · 2 guitars` — and approved signups fill those
until full. This same "needed roles + counts" structure also powers
**gaps-to-fill** (gaps = needs − approved), so it's one concept, two features.
Nobody gets ranked out.

### Contention & reservation semantics
A pending signup is an **application, not a reservation** — it never holds the slot:
- **Multiple people can be pending for the same spot at once** (the PK is per
  user, so several users can hold `pending` rows for the same song + instrument).
  This is what lets the approver *choose* among applicants — and what a
  track-record signal would later assist.
- **A slot is consumed only when a signup is `approved`.** Availability is simply
  `approved count for (song, instrument) < capacity`.
- **Rejection frees nothing** — a declined applicant never held the slot. What
  reopens a slot is an **approved** performer **withdrawing or being removed**
  (approved-count drops).
- **When a slot fills** (`approved == capacity`), no new applications are
  accepted; remaining pending applicants for that slot are resolved (see Open
  decisions).
- Enforced **server-side**: the status trigger rejects an approval that would push
  approved-count past capacity, so two simultaneous approvals can't over-fill.
- **No capacity declared → no scarcity → no contention**; approval is pure
  gatekeeping and any number can be approved.

### No "reservation" primitive needed — mode + capacity cover both philosophies
- **Compete & be chosen** → a manual mode (`organizer`/`proponent`) + capacity:
  many apply, the approver picks the lineup.
- **First-come-first-served** → `auto` + capacity: the first N to sign up are
  auto-approved and fill it — no pending, no holds.

*(The needed-roles/capacity structure is a small `performance_need` table; it can
land with gaps-to-fill.)*

## Deferred — track-record as a decision *aid*, not an auto-judge
Requested idea: when several people want a slot, weigh them by track record.
**Deferred and reshaped**, deliberately:
- An *automated* reputation-ranked audition is over-engineering now and tonally
  risky — it front-loads a reputation economy, invites gaming, and pushes an
  inclusive jam app toward gatekeeping newcomers.
- The tasteful form, *later*: show the human approver a **signal** next to each
  applicant ("played 12 toques · 140 applause · no no-shows") to help them choose —
  augmenting the person, not replacing them.
- It's naturally gated behind the data it needs: applause history (Showtime) and
  attendance/reliability (RSVP + no-show tracking). Revisit in the Encore phase.

## Surfaces
- **Signup control** — in a manual mode the button reads "Request to play" with a
  "pending" state; in `invite_only` there's no public signup, just an invite flow.
- **Approval queue** — per toque (organizer) or per song (proponent), approve/decline, batch.
- **Toque settings** — the mode selector (organizer only).

## Notifications (Phase 2 tie-in)
- Manual signup → the approver notified ("X wants to play bass on <song>").
- Approve/decline → performer notified.

## Open decisions
- **When a slot fills** — auto-decline the remaining pending applicants (reason
  `slot_filled`, with a notification), or keep them as a **waitlist** that
  auto-promotes if an approved performer withdraws? Recommend auto-decline for
  simplicity; waitlist is the resilient-to-no-shows alternative.
- **Capacity model timing** — ship needed-roles/caps with this, or with gaps-to-fill? (Lean: with gaps-to-fill; they're the same structure.)
- **Re-request after decline** — allow (recommend) vs block on the same slot.
- **Venue-level default** for the mode — skip for now.

## Dependencies / feeds
- **Needs:** party status model (signups open only while `confirmed`).
- **Feeds:** live "who's on it", applause participants, gaps-to-fill, notifications.
- **Reuses:** the `auto_add_admin` trigger pattern; the party-admin membership
  check used across the hardened RLS; `performance.suggested_by` (the proponent).
- **Later:** track-record signal depends on applause + attendance history.
