# Band sets: making a band's block a real thing you can move

**Status:** stage 1 (schema + RPCs) written, awaiting apply · **Issue:** #110 · **Extends:** #40 (bands) / #37 (live mode)

## The problem

A band playing eight songs is eight `performance` rows that happen to share a
`band_id`. Nothing in the model says they belong together, so:

- **Moving the band in the running order means moving eight songs**, one
  ChevronUp press at a time. To move Pulse's ten-song set from the top of
  Halloween Fest to the bottom is fifty-odd presses.
- **Nothing keeps the block together.** This is not hypothetical — it has
  already happened:

  | Toque | Shape | |
  |---|---|---|
  | Amistad y Amor por el Rock | 10 band / 0 open | contiguous |
  | Halloween Fest | 10 band / 5 open | contiguous |
  | **Monster Mash** | **2 band / 19 open** | **INTERLEAVED** — the band's two songs are split apart by open songs |

- **A band cannot arrange its own set.** Reordering is `performance` UPDATE,
  which is party-admin only, so the band has to ask the organizer to move its
  own songs around.

## "Should a band's set be a single performance?"

The instinct is right and the mechanism is not. The set does need to be **one
atomic, orderable, permission-bearing thing** — that is exactly what is missing.
But it cannot *be* a performance, because a performance is already carrying four
things that are per-song and would be destroyed by collapsing:

| Per-song thing | What collapsing costs |
|---|---|
| `live_state` | The now-playing pointer **is** `live_state = 'playing'` (#37). One row per set means the audience view can only say "Pulse is on", never which song. |
| `applause` | Four target types, two of them per-performance (`song`, `song_performer`), each with its own partial unique index. A set-level row erases song-level claps. |
| `performance_user` | Who plays what instrument **on that song**. A guest on one number, the singer sitting out another. |
| `started_at` / `ended_at` | Per-song timing, which song applause windows read. |

So the answer to "but then how do we order them within the set" is: **you do not
collapse — you add a level above.** The set is a *container* of performances, not
a replacement for them. Ordering becomes two-level, which is the natural shape of
the thing being modelled: a night is a sequence of sets, a set is a sequence of
songs.

## The model

```sql
create table party_set (
  id         bigint primary key,
  party_id   bigint not null references party (id) on delete cascade,
  band_id    bigint references band (id),   -- NULL = open slot, anyone may add
  "order"    smallint not null,             -- position in the night
  title      text,                          -- optional: "Jam abierto", "Cierre"
  created_at timestamptz not null default now()
);

alter table performance add column set_id bigint references party_set (id);
```

**Every performance belongs to a set.** A pure jam night is one party with one
open set — the current behaviour, unchanged, just with a container around it. A
band showcase is N band sets. A mixed night alternates. `performance."order"`
stops meaning "position in the night" and starts meaning "position in my set".

An **open set** (`band_id is null`) is what makes mixed events work without a
special case: the five loose songs at Halloween Fest become an open set sitting
after Pulse's, and the organizer can move either block as a unit.

## How it behaves — three mechanism questions, answered

These were asked of the first draft and they settle three of its open questions.
The answers are what make the two-level model feel like one list rather than
like folders.

### Open sets are implicit

Nobody creates, names or manages an open set. It is created when a loose song
needs somewhere to live and **garbage-collected when its last song leaves**.

That has a consequence worth stating plainly: **a band set is a visible block
with a header; open songs render as plain rows.** For a pure jam night — which
is most nights — the screen looks exactly as it does today. The band block is
the only new visual element.

### Adding: position says where, never a picker

The main "Agregar canción" at the bottom of the night adds an **open** song at
the end. If the last block is an open set it joins it; if the last block is a
**band** set, a new open set is created after it. The implicit-set rule does the
work and the user never learns the concept.

**A band's block carries its own `+`**, which adds to that set. **Decided:**
positional rather than inferred. The alternative — one button that silently
routes a band member's song into their own set — behaves differently for
different people pressing the same control, which is the kind of rule nobody can
predict and nobody can be told. A `+` inside Pulse's block adding to Pulse's set
needs no explanation at all.

That `+` is visible only to people who may actually use it: the band (per
`can_sign_up_band`) and party admins.

### Up/down skips over a band set, never into it

With `[Open A] [Pulse] [Open B]`, a song at the bottom of Open A pressing **down**
lands at the **top of Open B** — after Pulse, not inside it. If no open set
follows, one is created.

This is the answer to "does moving it down from the bottom of the first set move
it to the top of the next one?" — yes, but it hops the whole band block in one
press rather than walking through it.

Two reasons this is the rule rather than a compromise:

- **It is what the permission model wants anyway.** A stranger's song can never
  slide into a band's set by accident, because the movement that would do it does
  not exist.
- **Up/down cannot express a choice.** A single button cannot ask "over or into?".
  So the common case gets the button, and moving a song *into* a band set is a
  separate explicit action available to **that band** — not to party admins, per
  the ownership rule below.

### A band's block is collapsed by default

**Decided.** A band set renders as one line — band name, song count, and the
first few titles as a teaser — and expands on tap. Same move #107 just made for
resolved logistics rows, and for the same reason: three bands of ten songs is
thirty rows of something the reader is not currently acting on.

Open songs stay plain rows, so a pure jam night is unchanged.

**This has one consequence that must not be missed.** During a live show the
now-playing song may be inside a collapsed block, which would leave the audience
view showing a closed box while the band is on stage — the exact opposite of what
live mode is for. So:

- The set containing the `live_state = 'playing'` song is **always expanded**,
  and cannot be collapsed while it holds the pointer.
- When the show advances into a new set, that set expands and the previous one
  may collapse.

The teaser matters more than it looks. A collapsed block showing only "Pulse ·
10 canciones" hides the setlist from exactly the person deciding whether to come.
Showing "Pulse · 10 canciones · Even Flow, Dani California, Shy Away…" keeps the
page answering that question without the full thirty rows.

### A band can play more than once

Deliberately supported: there is **no unique constraint on `(party_id, band_id)`**.
A headliner playing two sets with an open block between them is a normal shape
for this kind of night, and it is also why Monster Mash's split block should
become two sets rather than being merged.

The consequence is in the UI, not the schema: a set cannot be labelled by band
name alone when a band has two. That is what the optional `title` is for —
falling back to "Pulse · 2º set" when it is unset.

## Permissions — the crux, and why policies will not do it

This is the part that decides the shape. The requirement is:

- Organizers reorder **sets** within the night.
- A band reorders **songs within its own set** — and nowhere else.
- Non-members cannot slot a song **into** a band's set.
- **Organizers cannot either.** Refined after the first draft: a party admin can
  neither reorder, add to, nor remove from a band's set. *The organizer decides
  WHEN a band plays; the band decides WHAT it plays and in what order.* Deciding
  a band's running order is not the organizer's call, and "a band cannot arrange
  its own set" is one of the three problems this ticket opened with — a rule that
  left the organizer able to overrule them would only half-fix it.

  The organizer's remedy if a band goes quiet is the one they already have:
  delete the set, which cascades its songs. `party_set` rows stay admin-only, so
  booking a band into the night, moving its block and removing it are all still
  theirs. The split is **contents vs position**.

Two facts make this an RPC job rather than a policy job:

**1. `performance` UPDATE is already narrow, and widening it is the wrong tool.**
It is currently party-admin only (creator or `party_admin`) — *note that
CLAUDE.md is stale here, it still describes this as `using true`*. To let a band
reorder its own songs you would widen UPDATE to band members, and **RLS cannot
restrict which columns an UPDATE touches**. That hands band members `song`,
`party`, `live_state`, `key` and `band_id` on those rows. Same limitation that
forced #95's `confirm_requirement`, #100's `set_song_reviewed` and the whole of
#99 into SECURITY DEFINER RPCs.

**2. `performance` INSERT is `with check (true)`.** Anyone signed in can insert a
performance into any party today. "Non-members cannot slot songs into a band's
set" is currently unenforceable at the database, and that stays true no matter
what the UI does.

So:

```
reorder_sets(p_party, p_set_ids bigint[])              -- party admins
reorder_set_songs(p_set, p_performance_ids bigint[])   -- whoever OWNS the set
move_song_to_set(p_performance, p_set, p_position)     -- can_edit_set BOTH ends
```

**The third one was missing from this spec's first draft**, and the question that
found it was *"how does a band move a song between its own two sets?"* — which
this spec explicitly allows, since a band may play twice in a night. Both reorder
RPCs write only `"order"`; moving between sets needs `set_id`.

The tempting answer was to make cross-set moves party-admin-only, since admins
already hold `performance` UPDATE. That is wrong: it sends a band to the
organizer to rearrange its own material, which is the complaint this ticket
exists to fix.

The rule is not about who the caller is but about **which two sets they touch**:
you may move a song when you can edit *both ends*. `can_edit_set()` already
answers that, and everything falls out with no special cases:

`can_edit_set()` now answers "who owns this set" rather than "is this person
important", which makes the table fall out with no special cases at all:

| Move | Source / target | |
|---|---|---|
| Pulse set 1 → Pulse set 3 | band / band | allowed |
| Band → an open block | band / organizer | refused |
| Band A → Band B's set | band / other band | refused |
| Admin → into a band's set | organizer / band | refused |
| Admin pulls a song out of a band's set | band / organizer | refused |
| Admin moves an open song over a band block | organizer / organizer | allowed |

The last row is the point: an admin can never land a song *inside* a band's
block, which the first draft wanted and got from a hand-written special case.
Here it falls out of the ownership rule.

So **"up/down skips over a band set" is not a separate mechanism** — it is this
one with both ends open.

Two consequences found while building it: the GC trigger fired only on `DELETE`,
so an open set emptied by a *move* would have been orphaned (it now fires on
`update of set_id` too); and `band_id` is synced to the destination set, so a
song's ownership never disagrees with the block it sits in.

Both SECURITY DEFINER, both writing **only** `"order"`, both validating that
every id passed belongs to the party/set in question — otherwise the array
argument becomes a way to reorder somebody else's night.

And the INSERT policy tightens to: the target set is open, **or** the inserter is
a member of `set.band_id`, **or** they are a party admin. That is worth doing on
its own merits, independent of this feature.

## A side benefit worth naming

Reordering today is `arr.map((p) => supabase.from('performance').update(...))` —
**one round trip per row, for every move.** Moving one song in a fifteen-song
list is fifteen UPDATE requests. An RPC taking an ordered array collapses that to
one call, which is the same class of fix as #84's request batching.

## Live mode has to learn the second level

**Three**, not four. `start_show`, `advance_show` and `skip_song` share an
identical `order by "order" nulls last, id limit 1` and each becomes
`order by s."order", pf."order"` over a left join to `party_set`.

`undo_last_move` was listed here in error: it orders by `ended_at desc`, i.e. by
what actually happened rather than by the running order, so it is correct as it
stands. `jump_to_song` and `end_current_song` do not order at all.

Contained, but it is the riskiest part of the change: the running order is what
the audience sees during a live show, and getting it wrong is visible to a room
full of people. Worth its own test pass against a test toque before it goes near
a real one.

## Migration

Derive sets from the contiguous runs already in the data.

**Correction to this spec's first draft: every toque derives cleanly, and no
decision is needed.** The claim that Monster Mash's band songs were "separated by
open songs" was a misreading. Checked against the database:

| Party | Derives to |
|---|---|
| 5 Serenata Rock | 1 open set (9) |
| 9 Happy Birthday Cami | 1 open set (23) |
| 10 Amistad y Amor | 1 band set (10) |
| 11 Monster Mash *(test)* | open (14) · band 1 (2) · open (5) |
| 25 Halloween Fest | band 2 (10) · open (5) |
| 37 Jojoprueba *(live)* | 1 open set (4) |

Monster Mash's two band songs are **adjacent** (orders 14 and 15); what sits
either side of them is open songs. That is an ordinary three-block night, not an
interleaving. Nothing is merged and no running order is rewritten.

One consequence worth noting: because nothing derives into two sets for the same
band, **the multi-set-per-band case is not exercised by the backfill** — it still
has to be tested by hand.

### Why the backfill does not renumber `performance."order"`

`"order"` changes meaning — from position-in-the-night to position-in-my-set —
but the backfill leaves the values alone. Sets are derived from runs that are
already contiguous, so within a set the existing values already ascend, and sets
are numbered in the order their songs already appear. Both readings therefore
agree, and the migration is safe to apply *before* the client deploy:

```
old client:  order by pf."order"              -> unchanged
new client:  order by s."order", pf."order"   -> identical, today
```

Verified as a query across all 82 performances: 0 rows left without a set, 0
duplicate assignments, and **0 parties whose running order changes**. Renumbering
to 1..n per set would have broken the live client the instant it ran.

## Decided

Everything the first draft left open has been settled. Three of them answered
themselves from what the codebase already does — worth recording *why*, so they
are not reopened later on taste.

**Which band members may reorder — `can_sign_up_band()`, not `is_band_manager()`.**
(Separate axis from the organizer question above: that one settles *whether an
organizer may at all* — no — and this one settles *which members* may.)
Not a new decision at all. `sign_band_up` already gates on that function, which
reads **`band.who_can_sign_up`** — a per-band setting the band itself chose.
Inventing a manager-only rule for reordering would contradict a setting the band
explicitly made, and would make *rearranging your own songs* stricter than
*committing the band to a gig*, which is backwards. (Both bands currently sit at
`'members'`.)

**A guest may play in a band's set — already true, keep it.** `sign_band_up`
populates `performance_user` from `band_member_instrument`, but
`performance_user` has its own independent signup path. So the set governs *which
songs are in the block*, not *who plays them*. That separation is worth stating
because it is load-bearing: a set is a scheduling unit, not a roster.

**A set gets no applause target.** `applause_target` could gain a `set` value —
a set has an id and the enum is extensible — but `event` already covers "the
whole night" and a per-set clap sits awkwardly between the two. Out of scope; the
shape does not preclude it.

**Removing a band deletes its songs.** `performance.set_id` gets
`on delete cascade`, behind one confirm that names the count — *"Quitar a Pulse
quita también sus 10 canciones"*. The signups go with them, which is correct: the
band is not playing. Leaving ten unclaimed songs in the night would only move the
cleanup to the organizer.

Guard this while a show is **live**: removing the set that holds the now-playing
pointer would strand `advance_show`. Refuse it during `live`, or require the show
to be ended first.

**Collapsed by default**, and **a `+` inside each band block** — both covered
above, with the live-mode consequence of the first being the thing most likely to
bite.

## How a band set comes into existence

The first draft never said, and it turned out nothing created one. The nine sets
that exist were derived by the backfill from historical contiguous runs;
`sign_band_up` wrote `performance.band_id` and never touched `set_id`. Found in
live test data — three songs on party 41 carrying `band_id = 3` while sitting in
an **open** set — which breaks the two things this ticket is for: the band cannot
reorder its own songs (an open set belongs to the organizer), and a set-based
setlist would render them as loose rows, *regressing* the block display that #74
already gives them.

**Decided: `sign_band_up` joins the band's set, creating one at the end of the
night if the band has none.** A band's songs are its block — that is the premise
of the whole feature, and nothing else was going to build it.

The trade, taken knowingly: a band can now put a block into someone else's
running order by signing up, and the song jumps from wherever it sat into that
block. The organizer's counterweight is unchanged — `party_set` writes stay
admin-only, so they can move the block or delete it (which cascades its songs, as
already decided). This is the **one** place a `party_set` row is created by
someone who is not a party admin, and it is safe only because `sign_band_up` is
`SECURITY DEFINER` and has already checked `can_sign_up_band()`.

When a band already plays twice, the song joins the **last** of its sets; the
band can move it with `move_song_to_set`.

## Verified against the database (2026-09-14)

Stage 1 is applied and every write path has now been exercised as a signed-in
user, against test party 11 (`[open 14] [band 2] [open 5]`) and capibear's test
party 41 / band 3. Party 11 was snapshotted first and restored field-for-field
afterwards; no stray rows or sets remain.

**Two bugs were found by running the code, neither visible in review.** Both were
cases where the SQL encoded a subtly different rule than the comment above it.

1. **`move_song_to_set` landed one slot early, and appends could land first.**
   The backfill deliberately does not renumber `"order"` — that is what let stage
   1 ship before the client — so sets still hold legacy *global* positions (party
   11's first set runs 0..13, its band set 14..15). The RPC treated `p_position`
   as 1-based and tied it against those raw values. Measured: position 1 landed
   at position 2; and an append into the band set computed `v_pos = 3` against
   orders 14 and 15, which would have put the song **first**. Fixed by
   normalising the destination to 1..n before inserting.

   *Lesson worth keeping: "the backfill does not renumber" is load-bearing for
   the deploy ordering, so nothing downstream may assume `"order"` is 1..n.*

2. **A loose song joined the last OPEN set rather than the last BLOCK.** With the
   night ordered `[open] [open] [band]`, a new song landed in the middle, ahead
   of the band — while the button that added it sits at the bottom of the list.
   That is precisely the shape this feature creates: the first time an organizer
   moves a band to the end of the night, everything added afterwards goes in
   front of them.

### What passed

| | |
|---|---|
| `reorder_sets` | reorders the night; refuses a wrong count, a foreign set id, a non-admin |
| `reorder_set_songs` | reorders within a set; refuses a wrong count and a song from another set |
| `move_song_to_set` | position 1, middle, and append all land correctly; `band_id` follows the set; refuses a cross-toque target |
| insert trigger | joins the trailing open block, and creates a new one when the night ends with a band set |
| GC trigger | removes an open set emptied by a **move** and by a **delete**; leaves an occupied one alone |
| **ownership** | a party admin who is **not** in the band is refused on that band's set — both `reorder_set_songs` ("you cannot rearrange this set") and `move_song_to_set` ("you cannot put a song into that set") |

The ownership row is the one the refinement was about, and it is now proven
end-to-end rather than argued: an organizer created a set for a band they do not
belong to (`party_set` writes are admin-only, as intended) and was then refused
on its contents.

### The ownership matrix, proven end to end

Closed using a second account's test toque (party 41, which the tester does not
administer) and Pulse (which they are in). Signing Pulse up created the set, so
this also exercises the new creation path:

| As | On | |
|---|---|---|
| organizer, not in the band | that band's set | **refused** — "you cannot rearrange this set" |
| organizer, not in the band | moving a song *into* that set | **refused** — "you cannot put a song into that set" |
| **band member, not an organizer** | **their own set** | **allowed** |
| band member, not an organizer | the night's running order | **refused** — "only a party admin can reorder" |
| band member, not an organizer | the organizer's open set | **refused** — "you cannot rearrange this set" |
| neither | anything | refused |

Both directions hold: the organizer owns *when*, the band owns *what*.

`sign_band_up` behaved as designed — the first signup created one Pulse set at
the end of the night and moved the song into it; the second joined the same set
rather than creating a second.

### Blocks merge, and songs hop over them — verified 2026-09-14

Run against test party 11, `[open 14][band 2][open 5]`:

| | |
|---|---|
| down from the last song of an open block | skips the band block whole, lands at the TOP of the next open one |
| up from the top of an open block | lands at the BOTTOM of the previous one — clean round trip |
| a band's song at either edge of its block | no-op; it stays in the band's block |
| reorder that puts two open blocks together | merged, both sequences preserved in order |
| night ends with a band's block, press down | new open block created after it |
| night starts with a band's block, press up | new open block created before it |
| delete a band's block sitting between two open ones | the two open blocks merge |

The last row is why merging needs a trigger and not just a call inside
`reorder_sets`: deleting a block is the commonest way two open blocks end up
adjacent. `normalize_party_sets` is guarded with `pg_trigger_depth()` so it
cannot recurse through its own deletes or the performance GC.

**Disabled states follow one rule**: UP is dead only on the first song of the
first block, DOWN only on the last song of the last. Anywhere else a song has
somewhere to go. The symmetric "create a block at the START" case exists purely
to make that true — without it, a night beginning with a band's block left the
first loose song's up arrow enabled and silently doing nothing.

*Band blocks are the one exception and stay bounded by themselves.* Only the
band sees those arrows, and moving a song out means writing to the organizer's
open block, which `can_edit_set` refuses — so an unbounded arrow there would be
enabled and inert, the exact bug the start-case fixed. Letting bands eject songs
into the open list would reverse the ownership decision and is not taken here.

Note test party 11's set IDs changed during this (4 and 6 became 19 and 21):
merging genuinely deletes a block rather than hiding it. Song order was rebuilt
identically.

### Open question this surfaced: a band cannot undo its own signup

Once a band signs up, it cannot get the song back out. Verified, all three routes
refused:

- `move_song_to_set` back to the open block — refused, the open set is the
  organizer's.
- a direct `performance` UPDATE — silently refused by RLS (**0 rows, no error**;
  this is the PostgREST trap CLAUDE.md warns about, and it reads like success
  unless you check `.select()`).
- deleting the now-empty-ish band set — refused, `party_set` writes are
  admin-only.

Withdrawal was already organizer-only before this ticket (`set_band_signup_status`
is admin/proponent-gated), so #110 does not make it worse in kind — but it now
also leaves a set behind that only the organizer can remove. Worth deciding
separately whether a band should be able to withdraw, and what happens to its
block when the last song leaves (the GC only collects *open* sets, deliberately).

## Out of scope

- **Set durations / scheduling by clock time.** "Pulse at 21:00" is a different
  feature and drags in soundcheck, changeover and overrun.
- **Drag-and-drop.** The app reorders with up/down buttons and no drag library;
  nested drag on mobile is its own project.
- **Dragging a song from one band's set into another's.** Rare and confusing;
  remove and re-add. Note this is *not* the same as the skip-over behaviour
  above, which is ordinary reordering and very much in scope.
