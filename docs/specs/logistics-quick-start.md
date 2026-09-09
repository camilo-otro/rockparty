# Logistics quick-start — a standard set at event creation

**Status:** specced, not started · **Extends:** #95 (event logistics, Stages 1–4
shipped) · **Builds on:** #30 (venue equipment)

## The problem

Logistics starts empty. Today an organizer has to open the party page, tap
"Agregar equipo o rol", pick an item, set a source, and repeat — eight or nine
times before the list reflects a normal rock gig. That is slow enough that most
people will not do it, and **the gap list only helps if it exists**. Stages 1–4
built a good tool nobody has a reason to fill in.

So: at the moment a toque is created, offer the standard set in one pass — a
switch per item, a stepper for quantity — and let the organizer answer the whole
thing in about fifteen seconds.

## The thing that makes this better than a generic preset

**The venue is already chosen when the toque is created**, and #30 already knows
what that venue has. So the step should not present a blank standard list — it
should arrive **pre-answered**:

- Items the venue provides: switched **on**, already marked `source = 'venue'`,
  quantity and notes carried across, shown with a "del local" chip.
- Everything else in the standard set: switched **on** but `unassigned`.
- Anything not standard: off, add it later on the party page.

The organizer's job shrinks to flicking off what they do not need and eyeballing
the quantities. And the output of the step *is* the gap list — which is the whole
point of #95.

## Where it goes

**Recommendation: a step AFTER the insert, not a wizard inside `PartyForm`.**

Creation currently does: insert party → `toastSuccess('Borrador creado — revísalo
y publícalo')` → `goto('/parties/<id>')`. The step slots into that beat, landing
on the quick-start instead of the party page, with the party page one tap away.

Three reasons this beats a step inside the form:

1. **`PartyForm` is shared with edit.** A multi-step wizard there complicates a
   component two routes depend on, for a concern only one of them has.
2. **Requirements need a `party_id`**, which does not exist until the insert. A
   pre-insert step would have to hold intent in memory and write it afterwards
   anyway — the same write, with more state to get wrong.
3. **Creating a toque is the most important action in the funnel.** A mandatory
   extra step is a real risk to it. Post-insert, the toque already exists, so
   "Saltar" costs the organizer nothing and the step can never block creation.

Alternatives considered: a collapsible section inside the create form (less
friction, but pre-insert and inside the shared component), and a true wizard
(most "designed", most invasive). Neither pays for itself.

## The standard set

Three ways to decide what "standard" means:

| | |
|---|---|
| **(a) Hardcode a list in the client** | Fastest. Brittle — ids or names drift, and tuning the set needs a deploy. |
| **(b) `equipment.is_basic` + `default_quantity`** | One small migration. Tunable from the SQL editor without a deploy, same "curated catalogue" treatment `equipment_suggestion` already gets, and lets `party_role` opt in the same way. |
| **(c) Derive from `category`** | No migration, but "sonido + backline, not escenario" is a guess that will be wrong for some venues and cannot be corrected. |

**Recommend (b).** The migration is trivial:

```sql
alter table public.equipment  add column if not exists is_basic boolean not null default false;
alter table public.equipment  add column if not exists default_quantity integer;
alter table public.party_role add column if not exists is_basic boolean not null default false;

-- A rock gig's floor, from the existing 11-item catalogue:
update public.equipment set is_basic = true, default_quantity = 1
  where name in ('Sistema de sonido (PA)', 'Consola de mezcla', 'Batería',
                 'Amplificador de guitarra', 'Amplificador de bajo');
update public.equipment set is_basic = true, default_quantity = 2 where name = 'Micrófonos';
update public.party_role set is_basic = true where name = 'Ingeniero de sonido';
```

Both catalogues are world-readable already, so no policy changes.

Note `party_role` gets `is_basic` but **not** `default_quantity` — the
`quantity_is_equipment_only` check constraint forbids a quantity on a role, and
the UI must not offer a stepper for one. That constraint is enforced at the
database, so getting it wrong is a 400, not silent bad data.

## The interaction

One screen, one list, no pagination. Per row:

- a **switch** (reuse the one built for "Datos de prueba" in the header —
  `role="switch"` + `aria-checked`, the only switch pattern in the app)
- the item name, plus a **"del local"** chip when the venue supplies it
- a **stepper** (− n +) for equipment only, shown when the row is on

Roles sit in their own short group at the bottom, switches only.

Two actions: **"Listo"** (writes and goes to the party page) and **"Saltar"**
(goes straight there). Skip must be as prominent as Listo — an organizer in a
hurry should not feel trapped.

Copy should frame the result as a to-do, not a scolding. Landing on the party
page with "6 sin resolver" in warm-base right after creating a toque reads as
failure unless the step has already said what it is: *"Marcamos lo que falta
conseguir — lo puedes resolver después."*

## Writing it

One bulk `insert`, not one per row (#84). Rows are exactly what Stages 1–2
already write, so nothing downstream changes:

```
kind, equipment_id | role_id, quantity,
source        = 'venue' when the venue provides it, else 'unassigned'
confirmed_at  = now() for venue rows (its profile already declares them), else null
notes         = the venue's equipment note, when carried across
```

**Idempotency.** The step runs once on a fresh toque, so the list is empty — but
do not rely on that. Skip any `equipment_id` already present, the same rule
`seedFromVenue` uses, so a back-button or a double-tap cannot duplicate. There is
deliberately no unique constraint to lean on here: two amps from two sources are
legitimately two rows (see the #95 spec).

## Out of scope

- **Assignment.** Who brings it belongs on the party page, where Stage 2 lives
  and where the people picker has the toque's roster.
- **Re-running after a venue change.** The party page's "Traer el equipo del
  local" already covers that, and covers it better because it can see what is
  already listed.
- **Editing the catalogue from the UI.** `is_basic` is tuned in the SQL editor,
  like every other lookup in this app.

## Worth deciding before building

1. **Should the standard set default ON or OFF?** This spec says **on** — a rock
   gig genuinely needs a PA, mics, drums and amps, and defaulting off makes the
   step a no-op for anyone who just taps Listo. The cost is that a venue with no
   recorded equipment produces six gaps immediately. Mitigated by copy, but it is
   a real first-impression risk and the opposite default is defensible.
2. **Should the step appear for a toque with no venue-recorded equipment?** It is
   most useful exactly then — but it is also six switches with nothing
   pre-answered, which is more work than value for some organizers.
3. **Does it belong on edit too?** A toque created before this shipped has no
   logistics and no way to bulk-add. The party page's add-one-at-a-time still
   works, but a "empezar con lo básico" button there would close that gap for
   every existing toque, including the 19 Sep one.
