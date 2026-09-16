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

  Cami's House      <full street address>    <mobile number>    Cami Soto
  Donde Naty        <street>                           Naty
```

Two real homes, one real phone number. Not a hypothetical: those rows are live.

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

```sql
create type party_visibility as enum ('public', 'unlisted', 'private');
alter table public.party add column visibility party_visibility not null default 'public';
```

- **public** — today's behaviour. Listed, browsable, flyer previews, anyone may
  RSVP or ask for a slot.
- **unlisted** — not in any list or search, but anyone with the link sees it.
  This is the cheap 80% case: "I don't want it browsable, but I will share the
  link in a WhatsApp group." It needs no invite table at all.
- **private** — invisible unless you are invited.

**Recommend shipping `unlisted` first.** It solves most of what people mean by
"private", costs one enum value and one clause in the party SELECT policy, and
requires none of the machinery below.

### What an invite is

```sql
create table party_invite (
  party_id   bigint not null references party (id) on delete cascade,
  user_id    uuid references profile (id) on delete cascade,
  claim_token uuid not null default gen_random_uuid(),
  invited_by uuid not null references profile (id),
  created_at timestamptz not null default now()
);
```

Mirrors `band_pending_member` (#79) deliberately: a row can name a `user_id` for
someone who has an account, or stand on its `claim_token` for someone who does
not, with a `peek_party_invite(token)` read the way `peek_band_claim` works. The
scene runs on WhatsApp; an invite that requires the recipient to already have an
account will not get used.

## The part that will actually cost the time: every path that leaks

`can_see_party()` is the natural choke point and already exists — but **it gates
only three tables today**: `performance`, `party_set`, `party_requirement`.
Everything below has its own, looser policy and must be brought in line, or
private means nothing.

| Path | Today | Needed |
|---|---|---|
| `party` SELECT | `status in (confirmed, live, completed) or creator/admin/venue-admin` | add the visibility rule |
| `party_rsvp` | `true` | `can_see_party(party_id)` |
| `party_admin` | `true` | `can_see_party(party_id)` |
| `applause` | `true` | `can_see_party(party_id)` |
| `performance_user` | approved rows public | also require `can_see_party` on the parent |
| `/flyer/[id]` | SSR, anon | falls back to the brand card automatically once RLS hides the party — verify, do not assume |
| `/invite/[id]` | SSR, anon | same |
| notifications | `notify_upcoming_toques` and the signup/status notifiers | must not name a private toque to a non-invited recipient |
| `og:title` on both SSR routes | per-event | a private toque must never render its title into a crawler-visible tag |

**The SSR wrinkle.** `/flyer/[id]` and `/invite/[id]` render server-side with no
session, so they are anonymous by construction. That is what makes them safe for
private toques automatically — and also means an **invited** user opening a
shared flyer link sees the generic card until the client hydrates. Either accept
that, or have the page re-render client-side once the session is known. Worth
deciding, because a link you were invited by that looks broken is worse than no
link.

## Decisions to make before building

1. **Venue: view/RPC, or split the table?** (see A). This shapes everything else.
2. **Do we ship `unlisted` alone first?** It is a fraction of the work and may be
   all that is wanted.
3. **What does an invite grant** — see it only, or see it *and* claim a slot
   without approval? They are different, and `performer_approval` already exists
   to express the second.
4. **Can an invited guest invite others?** Cheap to allow, impossible to walk
   back.
5. **Does a guest see the guest list?** For a house party the answer is probably
   yes among invitees and never publicly — but that is a product call, and #102
   set the precedent of publishing counts rather than names.
6. **Retro-fitting existing rows.** `Cami's House` and `Donde Naty` should come
   out of the migration already private. Should every `venue_type = 4` default to
   private, or is the flag set by hand?

## Out of scope

- Per-person permissions finer than "invited".
- Hiding a toque from someone who was already there — history stays.
- Encrypting anything. This is about who the database hands rows to, not storage.

## Do first, regardless

Closing the venue leak (A) does not depend on any of B's decisions and is the
part that is already exposed. `party_rsvp` being world-readable is in the same
category. Both are worth their own migration before the feature work starts.
