# Private toques, and venues that are somebody's home

**Status:** specced, not started · **Extends:** #67 (test-data visibility), #102 (venue_admin exposure)

## The gap is already open

This started as "we may want invite-only events". Checking the data first turned
up something that does not need an invite system to be a problem: **a private
home's street address and the host's phone number are readable by anyone on the
internet, with no account.**

`venue` SELECT is `to anon, authenticated using ((is_test = false) or is_dev())`.
Measured against production with the anon key — the one that ships inside the JS
bundle, so "public" means public:

```
GET /rest/v1/venue?select=name,address,whatsapp,contact_name&venue_type=eq.4

  <home venue>      <full street address>   <mobile number>   <resident's name>
  <home venue>      <street>                                  <resident's name>
```

Two real homes, one real phone number. Not a hypothetical: those rows are live.
The actual values are redacted here — this repo is public, and writing them down
to prove they were readable would have republished exactly what the fix removes.

The pattern in the data shows the intent was already there and unenforced —
public venues carry a NEIGHBOURHOOD (`Usaquen`, `Chapinero`, `Cedritos`) while
homes carry a precise address. People are hand-rolling the privacy the schema
does not offer.

Three other reads are wider than they look, all confirmed by policy:

| Table | SELECT policy | What it hands out |
|---|---|---|
| `party_rsvp` | `using (true)`, incl. anon | who is attending which toque |
| `party_admin` | `using (true)`, authenticated | who organises what |
| `applause` | `using (true)`, authenticated | who applauded whom |
| `performance_user` | approved rows public, incl. anon | who plays what, where, when |

For a house party, `party_rsvp` plus `venue.address` is a guest list and a home
address, joinable by a stranger in one request.

## Two features, not one

Worth separating, because one is a leak to close and the other is a feature to
build, and the first should not wait for the second.

**A. Venue privacy** — a venue that is someone's home should not publish its
exact address, *regardless of whether the toque there is private*. A public jam
at a private house is a normal thing, and the address should still only reach
people who are actually going.

**B. Event visibility** — a toque that only invited people can see at all.

A does most of the protecting. B is what the original ask was about.

## A. Venue privacy: area in public, address to guests

Split what a venue publishes:

```sql
alter table public.venue
  add column area    text,      -- "Usaquén" — always public
  add column private boolean not null default false;
-- `address` becomes the precise one, and stops being public
```

- **`area`** is the coarse, public location. Existing public venues already have
  exactly this in `address` and can be moved across by the migration.
- **`address`** becomes the exact street address, readable only by people with a
  reason to have it.
- **`private`** marks a venue whose address is never public. Default it from
  `venue_type` for existing rows — `Club Privado` (4) is the closest thing today
  — but it is the flag, not the type, that governs.

**Who gets the exact address of a private venue:**

- its venue admins (`is_venue_admin`)
- the organiser and admins of a toque booked there
- anyone with an approved signup or an RSVP on a toque there
- and, if B ships, anyone invited to one

RLS cannot restrict WHICH COLUMNS a SELECT returns, so this cannot be a policy —
the same wall that made every narrow write an RPC in #95/#99/#100. Two options:

1. **A view or an RPC** (`venue_for_viewer(vid)`) returning the address only when
   entitled, with the base table's SELECT narrowed to non-private columns.
2. **Split the table**: `venue` public, `venue_contact` (address, whatsapp,
   contact_name) behind its own policy.

Option 2 is more invasive but it is the honest shape, and it makes the rule
reviewable — you can see at a glance which table holds the sensitive columns.
**Decide before building.**

Note `whatsapp` and `contact_name` belong on the same side of the line as
`address`. They are the host's personal contact details.

## B. Event visibility

> **Status 2026-09-21.** Part A shipped, and so did every read path in the table
> below. What is left is this section: the visibility flag and invites. Tracked
> as #114, which is the reason it matters — see "Why unlisted is not enough".

```sql
create type party_visibility as enum ('public', 'unlisted', 'private');
alter table public.party add column visibility party_visibility not null default 'public';
```

- **public** — today's behaviour. Listed, browsable, flyer previews, anyone may
  RSVP or ask for a slot.
- **unlisted** — not in any list or search, but anyone with the link sees it.
  Cheap: one enum value, one clause in the party SELECT policy, no invite table.
- **private** — invisible unless you are invited.

### Why `unlisted` is not enough

An earlier draft recommended shipping `unlisted` alone. It is still the cheaper
half, but it does **not** close #114 — and #114 is the reason this is being
built.

The chain: `can_see_venue_contact` grants a private venue's address to anyone who
RSVP'd, and `party_rsvp` INSERT is `with check (user_id = auth.uid())` with no
condition on `party_id`. Unlisted hides a toque from lists while leaving the link
— and therefore the RSVP — open to anyone holding it. The key stays on the hook.
**Only `private`, plus a constrained RSVP insert, closes it.**

Ship both, but know which is which: `unlisted` is a browsing convenience,
`private` is the security boundary.

### Invites: the registered / unregistered split

The part worth getting right, because the scene runs on WhatsApp and an invite
that demands an account first will not get used.

Two mechanisms, not one:

```sql
-- 1. a named invite, for someone who already has an account
create table party_invite (
  party_id   bigint not null references party (id) on delete cascade,
  user_id    uuid   not null references profile (id) on delete cascade,
  invited_by uuid   not null references profile (id),
  created_at timestamptz not null default now(),
  primary key (party_id, user_id)
);

-- 2. ONE shareable link per toque, for everyone else
alter table public.party add column invite_token uuid not null default gen_random_uuid();
```

**Registered, named.** The organiser searches people — `searchPeople` exists and
the party form already uses it for co-organisers — and inserts a row. The guest
sees the toque in their lists immediately: no link, nothing to claim. This is the
precise case, for when you know who you are inviting.

**Everyone else.** One shared link. Opening it hits a public companion route that
reveals a deliberately thin preview through a DEFINER RPC; the guest signs in
with Google; claiming inserts their `party_invite` row. From then on they are in
the named case — the link was only the doorway.

```
peek_party_invite(p_token uuid)  -> title, date, venue NAME and AREA only, band names
claim_party_invite(p_token uuid) -> bigint (the party id), inserts party_invite
```

Both mirror `peek_band_claim` / `claim_band_member` (#79), which already solve
this exact problem for band rosters. Reuse their shape rather than inventing a
second vocabulary for the same idea.

**`peek_party_invite` must not leak the thing being protected.** A private toque
is usually at somebody's house, so the preview shows the venue NAME and `area`,
never `venue_contact`. The address arrives only once the invite row exists and
`can_see_venue_contact` starts answering true. Get this wrong and the invite link
becomes the leak.

### Why one token per toque, not a token per invite

The earlier draft put `claim_token` on every `party_invite` row, mirroring
`band_pending_member`. That inherits a problem `band-claim-link.md` records at
line 52: **every roster edit mints new tokens**, leaving a manager with a pile of
links they cannot tell apart.

A single `party.invite_token` avoids it, matches how a WhatsApp group actually
works, and is regenerable — `regenerate_band_claim` is the precedent for the
"this got out, kill it" control.

The cost is real and belongs in the UI: **the link is a bearer credential.**
Anyone holding it can claim an invite. Band claim links already make that trade.

### The token must not be readable

`party.invite_token` would sit on a table anyone can SELECT. The column-grant
pattern from `profile.email` and `band_pending_member.claim_token` applies, and
so does its warning: **a plain `revoke select (invite_token)` does nothing**,
because a table-level grant covers every column. Drop the table grant, re-grant
per column — and note `party` has a lot of columns, so that list must be
maintained, and one added later is invisible until someone notices.

Worth weighing instead: keep the token in a **separate one-row-per-party table**
with its own policy, so `party` keeps its simple table-level grant. More joins,
one fewer footgun.

### Prerequisite: the party SELECT policy inlines a subquery

```sql
OR EXISTS (SELECT 1 FROM party_admin pa WHERE pa.party_id = party.id AND pa.user_id = auth.uid())
```

CLAUDE.md is explicit that a table referenced inside a policy is read AS THE
CALLER, which is why guards are DEFINER helpers. This one predates the rule. It
became load-bearing on 2026-09-18, when `party_admin` gained a real policy that
itself calls `can_see_party` — which reads `party`. That is a mutual recursion
one edit away from "infinite recursion detected in policy".

It does not fire today; the app has been in continuous use since. But **replace
it with `is_party_admin(id)` before touching this policy for visibility.** Adding
an invite clause to a policy already this close to a cycle is how an outage
happens.

## The part that will actually cost the time: every path that leaks

`can_see_party()` is the natural choke point. It gates `performance`,
`party_set` and `party_requirement` — and, as of 2026-09-18, several more.

| Path | State | Needed |
|---|---|---|
| `party` SELECT | status / owner / admin + is_test | add the visibility rule; fix the inline subquery first |
| `party_rsvp` | ✅ own row or organiser (2026-09-18) | also constrain INSERT — that is #114 |
| `party_admin` | ✅ own / co-organiser / not hidden (2026-09-18) | — |
| `applause` | ✅ `can_see_party` (2026-09-18) | — |
| `venue_contact` | ✅ `can_see_venue_contact` | — |
| `venue_equipment` | ✅ same (2026-09-18) | — |
| `performance_user` | approved rows public | also require `can_see_party` on the parent |
| `/flyer/[id]` | SSR, anon | falls back to the brand card once RLS hides the party — verify, do not assume |
| `/invite/[id]` | SSR, anon | same |
| notifications | `notify_upcoming_toques`, signup/status notifiers | must not name a private toque to a non-invited recipient |
| `og:title` on both SSR routes | per-event | a private toque must never render its title into a crawler-visible tag |

**The SSR wrinkle.** `/flyer/[id]` and `/invite/[id]` render server-side with no
session, so they are anonymous by construction. That is what makes them safe for
private toques automatically — and also means an **invited** user opening a
shared flyer link sees the generic card until the client hydrates. Accept it, or
re-render client-side once the session is known. Worth deciding: a link you were
invited by that looks broken is worse than no link.

## Decisions to make before building

1. ~~**Venue: view/RPC, or split the table?**~~ Decided: split, shipped as
   `venue_contact`.
2. ~~**Ship `unlisted` alone first?**~~ Decided: no — it does not close #114.
   Ship both, and know which one is the boundary.
3. **What does an invite grant** — see it only, or see it *and* claim a slot
   without approval? Different things, and `performer_approval` already exists to
   express the second.
4. **Can an invited guest invite others?** Cheap to allow, impossible to walk
   back. The shareable link makes this true by default unless the link is
   organiser-only — so this is really a decision about who can see the link.
5. **Does a guest see the guest list?** `party_rsvp` now says no: own row or
   organiser. "Yes among invitees" is defensible for a house party, but it is a
   product call, and #102 set the precedent of publishing counts, not names.
6. **Retro-fitting existing rows.** Existing toques default to `public`, which is
   right — do not silently privatise history. The two home venues are already
   `private`; that is a venue flag and independent of this.
7. **What happens to an RSVP when a toque turns private?** Someone who RSVP'd
   while it was public already holds the key #114 is about. Revoke, keep, or
   convert them into invites?

## Out of scope

- Per-person permissions finer than "invited".
- Hiding a toque from someone who was already there — history stays.
- Encrypting anything. This is about who the database hands rows to, not storage.

## Done first, as planned — 2026-09-16 to 2026-09-18

Closing the venue leak (A) did not depend on any of B's decisions and was the
part already exposed, so it went first, as did `party_rsvp` being world-readable.
Both shipped as their own migrations before any of B started.

What that pass actually found, beyond the address:

- `venue.contact` held a bare mobile number, despite a schema comment calling it
  a "free-form handle". Which columns are sensitive is a question about the DATA.
- **`venue_equipment` was world-readable** — an itemised inventory of gear by
  brand and model at a named private home, and 23 of its 25 rows belonged to
  private homes. Worse than the address, and missed on the first pass because
  checking that the address was gone is not the same as reading the rest of the
  page.
- `party_admin.hidden` was a promise RLS did not keep: the app hid an organiser
  who opted out, the database returned the row anyway.

The remaining exposure is not a read path at all, which is why closing all of
them did not close it — see #114, and "Why `unlisted` is not enough" above.
