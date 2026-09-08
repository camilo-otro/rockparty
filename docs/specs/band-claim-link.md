# Claim link — turn a placeholder band member into a real one

**Status:** specced, not started · **Issue:** #79 · **Milestone:** Phase 4 — Encore
**Follows:** #78 (placeholder roster, shipped) · **Reused later by:** #95 Stage 5
(named sound engineers / MCs claiming their credits)

## What exists today

A band manager can already add someone who has no account:

```sql
band_pending_member (id, band_id, display_name, instrument_ids bigint[], created_at)
```

They show on the band page as roster entries with no avatar and no link. That is
#78, and it is shipped. What is missing is the second half: a way for that person
to arrive, sign up, and *become* the real member — inheriting the instruments the
manager already recorded, without the manager redoing the work.

## The shape of it

Manager copies a link → sends it over WhatsApp → the person opens it, signs in
with Google, confirms "yes, that's me" → they are a `band_member`, their
instruments come with them, and the placeholder is gone.

**The link is the credential and the consent.** No email is stored, nothing is
sent by us (free-tier-first), and possession of the link is what proves the
manager meant to invite this person. That is the same trade the app already makes
with flyer links, and it is the right one here — but it has consequences that
Security below has to answer honestly.

---

## Prerequisite — stop wholesale-replacing the roster

**This has to be fixed first or the feature silently breaks.**

`src/routes/bands/[id]/edit/+page.svelte` currently saves placeholders like this:

```js
// Placeholder members (#78): wholesale replace (small set).
await supabase.from('band_pending_member').delete().eq('band_id', bandId);
if (pendingMembers?.length) {
  await supabase.from('band_pending_member').insert(pendingMembers.map(...));
}
```

Every save deletes every placeholder and inserts fresh rows. Today that is
invisible: nothing references a placeholder's `id`, so churning them costs
nothing.

The moment a `claim_token` lives on those rows, **every roster edit mints new
tokens and every outstanding claim link dies** — with no error, no warning, and
no way for the manager to know. Someone edits the bio, and the four links they
sent yesterday are dead.

So Stage 0 is: change that save to a diff keyed on `id` — update the rows that
changed, insert the new ones, delete only the ones actually removed. Small
change, and it is worth doing on its own merits regardless.

---

## Schema

```sql
alter table public.band_pending_member
  add column claim_token uuid not null default gen_random_uuid();

create unique index on public.band_pending_member (claim_token);
```

`gen_random_uuid()` gives 122 bits of entropy from a function Postgres already
has — no bespoke token generation, nothing to get wrong.

### Keeping the token out of client reads

This is the security crux, and getting it wrong hands every claim link to
everyone who can see the band.

`band_pending_member` has `select ... using (public.can_see_band(band_id))`, so
its rows are already readable by any visitor. Add a column and the token is
readable too.

The fix is the pattern `profile.email` already uses
(`20260821_profile_email_privacy.sql`) — and note the warning in that migration,
because it applies verbatim: **a plain `revoke select (claim_token)` does
nothing**, since Supabase grants table-level SELECT and in Postgres a table-level
grant covers every column regardless of column-level revokes. Drop the
table-level grant, re-grant per column:

```sql
revoke select on public.band_pending_member from anon, authenticated;
grant select (id, band_id, display_name, instrument_ids, created_at)
  on public.band_pending_member to anon, authenticated;
```

After this `select=*` returns everything but the token, and `select=claim_token`
403s.

**Happily, nothing in the app breaks.** Every current read already uses an
explicit column list — `select('id, display_name, instrument_ids')` in both
`bands/[id]` and `bands/[id]/edit` — so there is no `select('*')` to fix. Worth
re-checking at build time rather than trusting this note.

**The manager still needs the token** to build the link, and can no longer read
it. That is what `band_claim_link()` below is for.

---

## Functions

Three, all `security definer set search_path = ''` with fully-qualified names,
matching `sign_band_up`. And on every one of them, `revoke ... from public` —
`create function` grants EXECUTE to PUBLIC and anon/authenticated inherit it, so
revoking from `anon, authenticated` alone is a no-op. This repo has already
shipped that exact bug once (`20260907_purge_revoke_from_public.sql`).

### `band_claim_link(p_pending_id bigint) returns uuid`

Returns the token so a manager can build the URL. Guarded by
`public.is_band_manager(band_id)`; raises otherwise. Granted to `authenticated`.

### `peek_band_claim(p_token uuid) returns table (band_name text, band_id bigint, display_name text, instruments text[], is_test boolean)`

Lets the claim page render "Te agregaron a **Pulse** como **Bajo**" *before*
anything is written, including to someone not yet logged in — so they know what
they are signing up for. Granted to `anon, authenticated`.

Returns nothing for an unknown token; the page shows a plain "este enlace ya no
es válido" either way, so a wrong token and a claimed token are indistinguishable.

This deliberately reveals a band name and a display name to whoever holds the
token. They were sent the link; that is the point.

### `claim_band_member(p_token uuid) returns bigint` (the band id)

The whole claim, in one transaction:

```sql
v_uid := (select auth.uid());
if v_uid is null then raise exception 'must be signed in'; end if;

-- The delete IS the claim: atomic, so two people racing the same link
-- produce exactly one winner and one clean failure.
delete from public.band_pending_member
  where claim_token = p_token
  returning * into v_pending;
if not found then raise exception 'claim link no longer valid'; end if;

-- A real user must not be pulled into a test band (#67/#76). SECURITY DEFINER
-- bypasses can_see_band(), so this check has to be explicit — the RLS policy
-- that normally hides test bands is not running here.
if (select is_test from public.band where id = v_pending.band_id)
   and not public.is_dev() then
  raise exception 'not available';
end if;

-- Already a member (claimed a second placeholder, or joined in the meantime):
-- merge rather than fail. The instruments are the thing worth keeping.
insert into public.band_member (band_id, user_id, role)
values (v_pending.band_id, v_uid, 'member')
on conflict (band_id, user_id) do nothing;

insert into public.band_member_instrument (band_id, user_id, instrument_id)
select v_pending.band_id, v_uid, unnest(v_pending.instrument_ids)
on conflict do nothing;

-- notify the band's managers (existing notification table + bell, #63)
```

`delete ... returning` as the claim step is the important detail: it makes the
link single-use at the database level rather than in application logic, so no
amount of double-clicking or racing produces two memberships. If anything after
it raises, the whole transaction rolls back and the placeholder is still there —
a failed claim leaves no wreckage.

---

## The claim page — `/bands/claim/[token]`

1. **Always peek first**, logged in or not, and render what the link is for.
2. **Logged out** → "Ingresar con Google", `redirectTo` back to this same URL.
   The flyer's `?rsvp=1` flow is the precedent for surviving the OAuth round trip.
3. **Logged in** → an explicit confirm: *"¿Eres tú? Te agregaron a Pulse como
   Bajo."* → Confirmar / No soy yo.

   **Do not auto-claim on load.** A link pasted into a group chat will be opened
   by the wrong person, and a bind that happens without a tap is one nobody chose.
   Per *augment the humans*, the tap is the consent.
4. **Claimed** → redirect to `/bands/<id>` with a success toast.
5. **Invalid / already claimed** → a themed dead-end with a link to the band if it
   is publicly visible, per the inline-load-error convention (a toast alone would
   leave a blank page).

### Manager side, on `bands/[id]/edit`

Per placeholder row: **Copiar enlace** (calls `band_claim_link`, writes to the
clipboard), and **Regenerar** for when a link went to the wrong person — a
`regenerate_band_claim(p_pending_id)` RPC that swaps in a new uuid and returns
it, invalidating the old link. Deleting the placeholder already works.

Copy should hand over the full absolute URL, ready to paste into WhatsApp.

---

## Security — what the link actually grants

Being straight about this rather than burying it: **anyone holding the link can
join that band as that placeholder.** There is no second factor. That is
inherent in a no-email, no-invite-table design, and it is the same bargain #78
already made by letting a manager name people freely.

What keeps it reasonable:

- **122 bits of entropy** — not enumerable.
- **Single-use**, enforced by `delete ... returning`, not by application logic.
- **Revocable and regenerable** by the manager at any time.
- **The blast radius is one band membership**, which a manager can undo by
  removing the member. It grants no read access beyond what band membership
  already grants, and no admin rights — `role` is always `'member'`.
- **A real user cannot be pulled into a test band**, checked explicitly because
  SECURITY DEFINER bypasses the RLS that would normally hide it.

Two things to weigh at build time:

- **The token travels through the OAuth redirect** as part of `redirectTo`, so it
  passes through Supabase and Google and lands in their logs. The alternative is
  stashing it in `sessionStorage` and redirecting to a bare `/bands/claim`. Since
  the link is already being pasted into WhatsApp, the URL is not a higher-grade
  secret than the chat it travels in — but if this is ever reused for something
  weightier than band membership (#95's role credits, say), revisit it.
- **No expiry.** Deliberate: an expiring link adds a failure mode ("this expired,
  ask again") for a token the manager can already regenerate or delete. Revisit
  only if links start leaking in practice.

---

## Reuse for #95 Stage 5

Event logistics wants the same move for a sound engineer typed in as a plain
name: claim your credits, arrive to a populated profile instead of a blank one.

**Reuse the pattern, not a shared table.** What generalises is the shape — a uuid
token on the placeholder row, column-level grants to keep it unreadable, a peek
function for the preview, `delete ... returning` for the atomic claim, and a
confirm-before-bind page. A polymorphic `claimable` table would need a kind
discriminator and nullable FKs to serve two callers, which is more machinery than
writing the second RPC.

The one thing genuinely worth sharing is the claim *page*, if the URL becomes
`/claim/<token>` with the peek telling it what kind of thing it is looking at.
Worth deciding when the second caller actually exists, not now.

---

## Out of scope

- **Email invitations** — no outbound email on the free tier, and no PII stored.
  The link is the whole mechanism.
- **Auto-matching by email on signup** (the "optional later" in #79). It needs
  stored emails to match against, which #78 deliberately avoided.
- **Claiming into a manager role.** Always `'member'`; a manager can promote
  afterwards.

## Build order

0. Diff-based roster save (the prerequisite above) — independently worth doing.
1. Migration: column, unique index, column-level grants, the four functions with
   `revoke ... from public`. Then reconcile `supabase/schema.sql` and regenerate
   `src/lib/database.types.ts`.
2. Manager UI: copy link + regenerate on `bands/[id]/edit`.
3. `/bands/claim/[token]`: peek → login → confirm → claim.
4. Notify managers on claim.

## Verification worth doing explicitly

- Two browsers racing the same link → exactly one member, one clean error.
- `select=claim_token` from the client → 403; `select=*` → token absent.
- A non-manager calling `band_claim_link` → refused.
- An anon calling each function directly over REST → only `peek_band_claim`
  answers.
- A roster edit after Stage 0 → outstanding links still work.
- Claiming while already a member → instruments merge, no duplicate row, no error.
