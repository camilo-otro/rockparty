# Musician approval mode — requirement spec

**Status:** Draft · captured 2026-08-20 · roadmap phase: **Doors** (Phase 1)

## Purpose
Let an organizer decide whether musicians who sign up to play are approved
automatically or need manual acceptance. It's the performer-side mirror of the
venue-approval flow: the venue approves the *event*; the organizer approves the
*players*.

## The setting
`party.performer_approval` enum: `auto | manual`, **default `auto`**.

Deliberate asymmetry with `venue.requires_approval` (which defaults to `true`):
a venue approval protects the venue from unwanted events, so it's cautious by
default; most jams *want* open signups, so performer approval is opt-in curation.
Kept toque-level (a venue default can be inherited later if asked for).

## Signup lifecycle
`performance_user` gains `status`: `pending | approved | declined`.
- **auto** — a signup is `approved` immediately (today's behavior; fully backward-compatible).
- **manual** — the signup lands `pending`; the organizer accepts (→ approved) or declines (→ declined).
- **Admin exception** — if the person signing up is already a party admin, they're
  auto-approved regardless of mode (parallel to "organizer is a venue admin →
  skip pending_venue").
- `declined` is terminal for that signup; the performer can always withdraw
  (delete their own row) and re-request.

Approval grain = one `performance_user` row (this person, this instrument, this
song). The organizer's queue can batch-approve many at once.

## Status must be server-enforced (the crux)
A performer cannot be trusted to set their own `status`, so it is **not a
client-writable field**. A trigger owns it (same pattern as the existing
`auto_add_admin`):

- **BEFORE INSERT on performance_user** — set `status` from the parent party's
  mode: party admin → `approved`; else manual → `pending`; else → `approved`.
  Any client-supplied value is ignored.
- **BEFORE UPDATE on performance_user** — reject any change to `status` unless
  `auth.uid()` is a party admin.

Result: status is trustworthy no matter what the client sends.

## RLS changes
- **INSERT** — tighten from today's `with check (true)` (which lets anyone insert
  a signup *for anyone*) to `user_id = (select auth.uid())` **OR** party admin.
  This is a real fix independent of this feature.
- **UPDATE** — expand from own-user-only to also allow party admins (to approve /
  decline); the trigger still blocks performers from flipping `status`.
- **DELETE** — own-user (withdraw) or party admin (remove). (Currently own-user;
  add admin.)
- **SELECT** — narrow so `approved` signups are public, but `pending`/`declined`
  are visible only to the row's `user_id` or party admins. Mirrors the
  draft-visibility narrowing in `party-status.md`.

## What "approved" gates
Approved signups are the ones that count as *on stage*:
- public "who's playing" on the party / performance,
- live mode's "who's on it",
- applause participants (only approved performers are on stage),
- a filled gap ("needs a bassist" clears only when an approved bassist signs on).

Pending signups surface to the organizer as an approval queue (batch-approvable),
mirroring the venue's `pending_venue` queue.

## Surfaces
- **Signup control** — in manual mode the button reads "Request to play" and shows
  a "pending" state until accepted.
- **Organizer approval queue** — per toque, list pending requests with
  approve / decline (and batch).
- **Toque settings** — the `auto | manual` toggle (organizer only).

## Notifications (Phase 2 tie-in)
- Manual signup → organizer notified ("X wants to play bass on <song>").
- Approve / decline → performer notified.

## Open decisions
- **Re-request after decline** — allow freely (via withdraw + re-signup) or block
  a re-request on the same slot? Recommend allow; it's low-stakes.
- **Venue-level default** for `performer_approval` — skip for now; inherit later if wanted.
- **Notify on decline** — silent vs a gentle note. Recommend a gentle note once notifications exist.

## Dependencies / feeds
- **Needs:** party status model (signups are open only while `confirmed`).
- **Feeds:** live mode / "who's on it", applause participants, gaps-to-fill,
  notifications.
- **Reuses:** the trigger pattern already in the DB (`auto_add_admin`); the
  party-admin membership check used across the RLS we hardened.
