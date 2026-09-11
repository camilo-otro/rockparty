# Band sets: making a band's block a real thing you can move

**Status:** specced, not started · **Extends:** #40 (bands) / #37 (live mode)

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

## Open questions

1. **Who in a band may reorder — any member, or managers only?** `is_band_manager()`
   exists and `band_member.role` is manager/member. Managers is the safer default;
   any-member is friendlier. This is a product call.
2. **Can a band's set contain a song where a non-member plays?** A guest sitting
   in. `performance_user` is independent of set ownership, so yes by default —
   worth confirming that is wanted.
3. **What happens when a band drops off the lineup?** Does the set delete with its
   songs, or do the songs fall back into an open set? Deleting is cleaner;
   falling back is kinder to the people who signed up.
4. **Is the open set implicit or explicit?** Auto-create one per party so there is
   always somewhere to add a loose song, or make the organizer create it. Implicit
   is less to explain; explicit makes "this night is bands only" expressible.
5. **Does a set need its own applause target?** `applause_target` is an enum with
   four values; adding `set` is possible. Out of scope here, but the shape should
   not preclude it.
6. **Nested reordering on a phone.** Two levels of up/down buttons is a lot of
   chrome in a list that is already dense. Worth a look at whether sets collapse
   to a single line when not being edited — the same move #107 made for logistics.

## Out of scope

- **Set durations / scheduling by clock time.** "Pulse at 21:00" is a different
  feature and drags in soundcheck, changeover and overrun.
- **Drag-and-drop.** The app reorders with up/down buttons and no drag library;
  nested drag on mobile is its own project.
- **Cross-set moves.** Moving a song from one band's set to another is a rare,
  confusing action. Remove and re-add.
