# Band sets: making a band's block a real thing you can move

**Status:** specced, decisions settled, not started · **Issue:** #110 · **Extends:** #40 (bands) / #37 (live mode)

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
  separate explicit action available to party admins and that band's members.

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
reorder_set_songs(p_set, p_performance_ids bigint[])   -- party admins OR that band
```

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

Four RPCs walk the sequence and order by `"order"`: `start_show`,
`advance_show`, `skip_song`, `undo_last_move`. Each becomes
`order by s."order", pf."order"` over a join to `party_set`. `jump_to_song` and
`end_current_song` do not order and are unaffected.

Contained, but it is the riskiest part of the change: the running order is what
the audience sees during a live show, and getting it wrong is visible to a room
full of people. Worth its own test pass against a test toque before it goes near
a real one.

## Migration

Derive sets from the contiguous runs already in the data. Two of the three
affected toques derive cleanly; **Monster Mash does not** and needs a decision:

- Its band's two songs are separated by open songs. Merging them into one set
  **changes the running order** of a real (if past) toque.
- Alternatives: two sets for the same band — the schema allows it and the UI must
  not assume one-set-per-band anyway — or leave it and let the organizer sort it
  out with the new controls.

Recommend **two sets**: it is lossless, it exercises the multi-set-per-band case
immediately, and it does not rewrite history.

## Decided

Everything the first draft left open has been settled. Three of them answered
themselves from what the codebase already does — worth recording *why*, so they
are not reopened later on taste.

**Who in a band may reorder — `can_sign_up_band()`, not `is_band_manager()`.**
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

## Out of scope

- **Set durations / scheduling by clock time.** "Pulse at 21:00" is a different
  feature and drags in soundcheck, changeover and overrun.
- **Drag-and-drop.** The app reorders with up/down buttons and no drag library;
  nested drag on mobile is its own project.
- **Dragging a song from one band's set into another's.** Rare and confusing;
  remove and re-add. Note this is *not* the same as the skip-over behaviour
  above, which is ordinary reordering and very much in scope.
