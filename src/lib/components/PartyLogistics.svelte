<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { Plus, Trash2, AlertTriangle, Check, Download, X, UserPlus, Square, CheckSquare, History, ChevronDown, ChevronUp } from 'lucide-svelte';
  import { reportError, toastSuccess } from '$lib/stores/toasts';

  // Event logistics (#95). Stage 1: what this toque needs and where each piece
  // comes from, with the GAP LIST as the headline. Stage 2: a name on it, a
  // notification, and the assignee's own confirm/decline.
  export let partyId: number;
  export let venueId: number | null = null;
  export let canAdmin = false;
  export let currentUserId: string | null = null;
  // People already attached to this toque — its musicians and organizers. Passed
  // in rather than fetched: the page has them, and a global user search would
  // mean the unbounded profile query #92 is trying to remove.
  export let people: { id: string; nickname: string }[] = [];
  // The toque's organizers specifically (creator + party_admin), a subset of
  // `people`. Needed because "Organizador" only names a specific person when
  // there is exactly one — see setSource.
  export let organizers: { id: string; nickname: string }[] = [];
  // 'full'      — the planning surface on the party page: add, source, assign.
  // 'checklist' — the day-of load-in list on the live console: names and ticks,
  //               nothing to edit while you are running a show one-thumbed.
  export let mode: 'full' | 'checklist' = 'full';

  type Requirement = {
    id: number;
    kind: 'equipment' | 'role';
    equipment_id: number | null;
    role_id: number | null;
    quantity: number | null;
    source: 'unassigned' | 'venue' | 'organizer' | 'performer' | 'external';
    assigned_user: string | null;
    assigned_label: string | null;
    notes: string | null;
    confirmed_at: string | null;
    checked_at: string | null;
  };

  const COLS =
    'id, kind, equipment_id, role_id, quantity, source, assigned_user, assigned_label, notes, confirmed_at, checked_at';

  let requirements: Requirement[] = [];
  let loaded = false;
  let busy = false;

  let equipment: { id: number; name: string; category: string | null; default_quantity: number | null }[] = [];
  let roles: { id: number; name: string }[] = [];
  let catalogueLoaded = false;
  let venueEquipment: { equipment_id: number; quantity: number | null; notes: string | null }[] = [];

  let adding = false;
  let formKind: 'equipment' | 'role' = 'equipment';
  let formItemId = '';
  let formQuantity = '';
  let formSource: Requirement['source'] = 'unassigned';
  let formNotes = '';

  // Rows whose editors are open (#107). A RESOLVED row hides its two selects by
  // default: they offer to change a decision already made, and they are two
  // thirds of the row's height. Unresolved rows always show them — the source
  // picker is the whole point of the screen — so this set only ever concerns
  // resolved ones.
  //
  // Session-only, and a Set that must be REASSIGNED, never mutated: legacy mode
  // tracks `expanded` by name, and an in-place .add() changes nothing it can see.
  let expanded = new Set<number>();
  // Which row is asking "¿Quitar?". Removal is a plain DELETE with no undo — the
  // toast store has no action support — so it gets a second tap. Same inline
  // Check/X idiom this component already uses for the typed-name flow.
  let confirmingRemove: number | null = null;

  function toggleExpanded(id: number) {
    const next = new Set(expanded);
    next.has(id) ? next.delete(id) : next.add(id);
    expanded = next;
    // Collapsing must not leave a half-armed delete behind for next time.
    if (confirmingRemove === id) confirmingRemove = null;
  }

  // Which row is showing its "someone not on the app" text field.
  let namingFor: number | null = null;
  let typedName = '';

  // "Who brought this last time?" (#95 Stage 4). The record Stage 2 has been
  // writing, read back at the one moment it is useful: while you are adding the
  // thing. No schema — one indexed lookup over rows that already exist.
  let lastTime: { assigned_user: string | null; assigned_label: string } | null = null;
  let lastTimeSeq = 0;
  let useLastTime = false;

  const SOURCE_LABEL: Record<Requirement['source'], string> = {
    unassigned: 'Sin resolver',
    venue: 'Del local',
    organizer: 'Organizador',
    performer: 'Lo trae un músico',
    external: 'Alquilado o externo'
  };
  const SOURCE_ORDER: Requirement['source'][] = ['unassigned', 'venue', 'organizer', 'performer', 'external'];

  onMount(async () => {
    // Anonymous visitors fetch nothing. A signed-in non-admin fetches only the
    // rows assigned to THEM — indexed, and usually zero.
    if (!canAdmin && !currentUserId) return;
    const base = supabase.from('party_requirement').select(COLS).eq('party_id', partyId);
    const [reqRes, veRes] = await Promise.all([
      canAdmin ? base.order('id', { ascending: true }) : base.eq('assigned_user', currentUserId!),
      canAdmin && venueId
        ? supabase.from('venue_equipment').select('equipment_id, quantity, notes').eq('venue_id', venueId)
        : Promise.resolve({ data: [] as any[] })
    ]);
    requirements = (reqRes.data ?? []) as unknown as Requirement[];
    venueEquipment = veRes.data ?? [];
    if (requirements.length) await loadCatalogue();
    loaded = true;
  });

  async function loadCatalogue() {
    if (catalogueLoaded) return;
    const [eqRes, roleRes] = await Promise.all([
      supabase.from('equipment').select('id, name, category, default_quantity').order('id'),
      supabase.from('party_role').select('id, name').order('id')
    ]);
    equipment = eqRes.data ?? [];
    roles = roleRes.data ?? [];
    catalogueLoaded = true;
  }

  // Derived maps, not helper functions: legacy mode tracks dependencies by NAME,
  // so a function reading `equipment` internally would leave the template stale
  // when the catalogue lands.
  $: equipmentName = Object.fromEntries(equipment.map((e) => [e.id, e.name]));
  $: roleName = Object.fromEntries(roles.map((r) => [r.id, r.name]));
  $: equipmentByCategory = equipment.reduce((acc: Record<string, typeof equipment>, e) => {
    (acc[e.category ?? 'otros'] ??= []).push(e);
    return acc;
  }, {});

  // Editors visible: always for a gap, on request for anything resolved. Derived
  // rather than a helper called from the template — a function reading
  // `expanded` internally would leave the markup stale when it changes.
  $: editing = new Set(
    requirements.filter((r) => r.source === 'unassigned' || expanded.has(r.id)).map((r) => r.id)
  );

  $: gaps = requirements.filter((r) => r.source === 'unassigned').length;
  $: grouped = SOURCE_ORDER.map((source) => ({
    source,
    label: SOURCE_LABEL[source],
    items: requirements.filter((r) => r.source === source)
  })).filter((g) => g.items.length);

  // Mine and not yet answered — the only thing a non-admin sees.
  $: mine = requirements.filter((r) => currentUserId && r.assigned_user === currentUserId);
  $: mineUnconfirmed = mine.filter((r) => !r.confirmed_at);

  // Day-of progress (#95 Stage 3). Only resolved rows count: something nobody is
  // bringing cannot be "here", and letting it be ticked would turn the checklist
  // into a way to make the gap disappear rather than close it.
  $: checkable = requirements.filter((r) => r.source !== 'unassigned');
  $: checkedCount = checkable.filter((r) => r.checked_at).length;

  $: alreadyListed = new Set(requirements.filter((r) => r.equipment_id).map((r) => r.equipment_id));
  $: seedable = venueEquipment.filter((ve) => !alreadyListed.has(ve.equipment_id));

  function label(r: Requirement) {
    const name = r.kind === 'equipment' ? equipmentName[r.equipment_id!] : roleName[r.role_id!];
    if (!name) return '…';
    return r.quantity && r.quantity > 1 ? `${name} ×${r.quantity}` : name;
  }

  function patch(id: number, fields: Partial<Requirement>) {
    requirements = requirements.map((x) => (x.id === id ? { ...x, ...fields } : x));
  }

  async function openAdd() { adding = true; await loadCatalogue(); }

  // Look up who last brought this item, on a toque THIS organizer created.
  // Scoped to their own history on purpose: someone else's arrangements are not
  // a useful suggestion, and it keeps the query to one indexed filter.
  //
  // `!inner` so the party filter actually restricts rows rather than just
  // nulling the embed. Latest-wins guard because the select fires per change.
  async function lookupLastTime(kind: 'equipment' | 'role', itemId: string) {
    const seq = ++lastTimeSeq;
    lastTime = null;
    // Never leave the quantity blank once an item is chosen. Uses the
    // catalogue's default_quantity (#97), which is 1 for everything except
    // Micrófonos — so "defaults to 1" holds, with the one item where a typical
    // toque needs more already right.
    if (kind === 'equipment' && itemId) {
      formQuantity = String(equipment.find((e) => e.id === Number(itemId))?.default_quantity ?? 1);
    } else {
      formQuantity = '';
    }
    if (!itemId || !currentUserId) return;
    const { data } = await supabase
      .from('party_requirement')
      .select('assigned_user, assigned_label, party!inner(created_by)')
      .eq(kind === 'equipment' ? 'equipment_id' : 'role_id', Number(itemId))
      .eq('party.created_by', currentUserId)
      .neq('party_id', partyId)
      .not('assigned_label', 'is', null)
      .order('id', { ascending: false })
      .limit(1);
    if (seq !== lastTimeSeq) return;          // a newer selection superseded this
    const row: any = (data ?? [])[0];
    lastTime = row ? { assigned_user: row.assigned_user, assigned_label: row.assigned_label } : null;
  }
  // A stepper, not <input type="number">. On a phone a number input opens the
  // numeric keypad over the form for a value that is almost always 1 and has
  // never plausibly been double digits. Matches the steppers VenueForm and the
  // #97 quick-start already use — this add form was the last raw number input.
  //
  // formQuantity stays a STRING: it is bound into the insert as
  // `Number(formQuantity)` and is '' while no item is chosen.
  function stepFormQuantity(delta: number) {
    formQuantity = String(Math.max(1, (Number(formQuantity) || 1) + delta));
  }

  function resetForm() { formItemId = ''; formQuantity = ''; formSource = 'unassigned'; formNotes = ''; lastTime = null; }

  async function addRequirement() {
    if (!formItemId || busy) return;
    busy = true;
    const { data, error } = await supabase
      .from('party_requirement')
      .insert({
        party_id: partyId,
        kind: formKind,
        source: formSource,
        // Same rule setSource uses: the venue's own profile already declares its
        // gear, so a row added as "Del local" arrives confirmed. Without this,
        // adding one that way and switching one to it produced different rows.
        confirmed_at: formSource === 'venue' ? new Date().toISOString() : null,
        notes: formNotes.trim() || null,
        equipment_id: formKind === 'equipment' ? Number(formItemId) : null,
        role_id: formKind === 'role' ? Number(formItemId) : null,
        quantity: formKind === 'equipment' && formQuantity ? Number(formQuantity) : null
      } as any)
      .select(COLS);
    busy = false;
    if (error) { reportError(error); return; }
    const created = (data ?? []) as unknown as Requirement[];
    requirements = [...requirements, ...created];
    // One tap: if they took the suggestion, the new row goes out already assigned
    // (and the Stage 2 trigger notifies that person, exactly as a manual assign
    // would).
    if (useLastTime && lastTime && created[0]) {
      await assign(created[0], lastTime.assigned_user, lastTime.assigned_label);
    }
    useLastTime = false;
    resetForm();
    adding = false;
  }

  async function setSource(r: Requirement, source: Requirement['source']) {
    const confirmed_at = source === 'venue' ? new Date().toISOString() : r.confirmed_at;
    // The venue supplying something is not a person bringing it, so an assignee
    // makes no sense — clear it rather than leaving a stale name attached to a
    // row whose picker is now hidden.
    const clearsAssignee = source === 'venue' && (r.assigned_user || r.assigned_label);
    let fields: Partial<Requirement> = clearsAssignee
      ? { source, confirmed_at, assigned_user: null, assigned_label: null }
      : { source, confirmed_at };

    // "Organizador" names a specific person only when there IS one. With a
    // single organizer that is unambiguous, so fill it in; with several it would
    // be a guess, and an unnamed row here is the "everyone assumed someone else
    // would bring it" failure — the picker stays for them to say who.
    if (source === 'organizer' && organizers.length === 1 && !r.assigned_user && !r.assigned_label) {
      fields = { ...fields, assigned_user: organizers[0].id, assigned_label: organizers[0].nickname };
    }
    const { error } = await supabase.from('party_requirement').update(fields).eq('id', r.id);
    if (error) { reportError(error); return; }
    patch(r.id, fields);
    // Picking a source is usually step one of two — assigning a person is step
    // two. Letting the row collapse the instant it stops being a gap would take
    // the assignee picker away mid-task, so keep it open until it is dismissed.
    if (!expanded.has(r.id)) expanded = new Set(expanded).add(r.id);
  }

  // Assigning someone. `assigned_label` is set even for app users — a snapshot of
  // the name at assignment time, so the record survives an account deletion and
  // the list renders without a profile join per row.
  async function assign(r: Requirement, userId: string | null, labelText: string | null) {
    // A row with a name on it is no longer "sin resolver"; leaving it there
    // would keep it in the gap count and make the counter lie.
    const source: Requirement['source'] =
      r.source !== 'unassigned' ? r.source
        : userId && userId === currentUserId ? 'organizer'
          : userId ? 'performer'
            : 'external';
    const fields = { assigned_user: userId, assigned_label: labelText, confirmed_at: null, source };
    const { error } = await supabase.from('party_requirement').update(fields).eq('id', r.id);
    if (error) { reportError(error); return; }
    patch(r.id, fields as Partial<Requirement>);
    namingFor = null;
    typedName = '';
  }

  function onAssignSelect(r: Requirement, value: string) {
    if (value === '__other') { namingFor = r.id; typedName = r.assigned_label ?? ''; return; }
    if (value === '') { assign(r, null, null); return; }
    // Re-selecting the already-assigned person keeps their snapshot name: they
    // may not be on this toque's roster, so `people` cannot supply it.
    const person = people.find((p) => p.id === value);
    const name = person?.nickname ?? (value === r.assigned_user ? r.assigned_label : null);
    assign(r, value, name ?? null);
  }

  async function saveTypedName(r: Requirement) {
    const clean = typedName.trim();
    if (!clean) { namingFor = null; return; }
    await assign(r, null, clean);
  }

  // The assignee answers. An RPC, not a direct update: RLS cannot restrict WHICH
  // COLUMNS an update touches, so a policy scoped to assigned_user would let an
  // assignee rewrite quantity or reassign the row.
  async function respond(r: Requirement, confirmed: boolean) {
    if (busy) return;
    busy = true;
    const { error } = await supabase.rpc('confirm_requirement', { p_id: r.id, p_confirmed: confirmed });
    busy = false;
    if (error) { reportError(error); return; }
    if (confirmed) {
      patch(r.id, { confirmed_at: new Date().toISOString() });
      toastSuccess('Confirmado. Gracias.');
    } else if (canAdmin) {
      // Declining hands the row back: it re-enters the gap count.
      patch(r.id, { assigned_user: null, assigned_label: null, confirmed_at: null, source: 'unassigned' });
      toastSuccess('Lo devolviste a la lista.');
    } else {
      requirements = requirements.filter((x) => x.id !== r.id);
      toastSuccess('Avisamos al organizador.');
    }
  }

  async function toggleChecked(r: Requirement) {
    if (r.source === 'unassigned') return;   // nothing to tick off yet
    const checked_at = r.checked_at ? null : new Date().toISOString();
    const { error } = await supabase.from('party_requirement').update({ checked_at }).eq('id', r.id);
    if (error) { reportError(error); return; }
    patch(r.id, { checked_at });
  }

  async function remove(r: Requirement) {
    const { error } = await supabase.from('party_requirement').delete().eq('id', r.id);
    if (error) { reportError(error); return; }
    confirmingRemove = null;
    requirements = requirements.filter((x) => x.id !== r.id);
  }

  // Explicit, never a trigger on venue change: an organizer's edits must not be
  // silently clobbered, and re-running it after a venue swap should be a choice.
  async function seedFromVenue() {
    if (!seedable.length || busy) return;
    busy = true;
    await loadCatalogue();
    const now = new Date().toISOString();
    const rows = seedable.map((ve) => ({
      party_id: partyId, kind: 'equipment' as const, equipment_id: ve.equipment_id,
      quantity: ve.quantity, source: 'venue' as const, notes: ve.notes, confirmed_at: now
    }));
    const { data, error } = await supabase.from('party_requirement').insert(rows as any).select(COLS);
    busy = false;
    if (error) { reportError(error); return; }
    requirements = [...requirements, ...((data ?? []) as unknown as Requirement[])];
    toastSuccess(`${rows.length} ${rows.length === 1 ? 'equipo' : 'equipos'} del local en la lista.`);
  }
</script>

{#if canAdmin || (loaded && mineUnconfirmed.length)}
  <div class="mt-6">
    <!-- What YOU were put down for. Shown to admins and non-admins alike; for a
         non-admin this is the only part of logistics they ever see. -->
    <!-- Gated on `loaded`: `requirements` is assigned before the catalogue is
         fetched, so without this the block renders one frame with label() at
         "…" before the names arrive. -->
    {#if loaded && mineUnconfirmed.length}
      <div class="mb-4 p-3 bg-base-900 rounded-lg border border-yellow/40 flex flex-col gap-2">
        <div class="text-yellow text-sm uppercase tracking-widest">Te toca</div>
        {#each mineUnconfirmed as r (r.id)}
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-white grow min-w-0">{label(r)}</span>
            <button type="button" on:click={() => respond(r, true)} disabled={busy}
              class="bg-cold-base text-white rounded-lg px-3 py-1 text-sm inline-flex items-center gap-1 disabled:opacity-60">
              <Check size={15} /> Lo llevo
            </button>
            <button type="button" on:click={() => respond(r, false)} disabled={busy}
              class="text-cold-light hover:text-white px-3 py-1 text-sm">No puedo</button>
          </div>
        {/each}
      </div>
    {/if}

    {#if canAdmin}
      <div class="flex items-center justify-between mb-2">
        <h3 class="{mode === 'checklist' ? 'text-lg text-white uppercase tracking-widest' : 'text-3xl text-white font-medium tracking-widest'}">
          {mode === 'checklist' ? 'Checklist del día' : 'LOGÍSTICA'}
        </h3>
        {#if loaded && requirements.length}
          {#if mode === 'checklist' && checkable.length}
            <span class="text-xs uppercase tracking-wide px-2 py-1 rounded-full {checkedCount === checkable.length ? 'border border-green-500 text-green-500' : 'border border-cold-light/40 text-cold-light'}">
              {checkedCount} de {checkable.length} listos
            </span>
          {:else if gaps}
            <span class="inline-flex items-center gap-1 text-xs uppercase tracking-wide px-2 py-1 rounded-full bg-warm-base text-white">
              <AlertTriangle size={13} /> {gaps} sin resolver
            </span>
          {:else}
            <span class="inline-flex items-center gap-1 text-xs uppercase tracking-wide px-2 py-1 rounded-full border border-green-500 text-green-500">
              <Check size={13} /> Todo resuelto
            </span>
          {/if}
        {/if}
      </div>

      {#if !loaded}
        <div class="text-cold-light px-1 py-2 text-sm">Cargando…</div>
      {:else}
        {#if !requirements.length}
          <p class="text-cold-light text-sm mb-3">
            Qué necesita este toque y de dónde sale. Empieza por lo que pone el local.
          </p>
        {/if}

        <ul class="flex flex-col gap-3 p-0">
          {#each grouped as group (group.source)}
            <li>
              <div class="text-xs uppercase tracking-widest mb-1 {group.source === 'unassigned' ? 'text-warm-base' : 'text-cold-light'}">
                {group.label}
              </div>
              <ul class="rounded-lg overflow-clip flex flex-col gap-[1px] p-0">
                {#each group.items as r (r.id)}
                  <li class="bg-base-900 px-3 py-2 flex flex-col gap-2">
                    <div class="flex items-start gap-2">
                      <!-- The tick. Absent on an unresolved row: you cannot mark
                           something present when nobody is bringing it, and
                           allowing it would let the gap be dismissed instead of
                           closed. -->
                      {#if r.source !== 'unassigned'}
                        <button type="button" on:click={() => toggleChecked(r)}
                          aria-pressed={!!r.checked_at}
                          aria-label="{r.checked_at ? 'Desmarcar' : 'Marcar como listo'} {label(r)}"
                          class="p-1 shrink-0 {r.checked_at ? 'text-green-500' : 'text-cold-light/50 hover:text-cold-light'}">
                          {#if r.checked_at}<CheckSquare size={20} />{:else}<Square size={20} />{/if}
                        </button>
                      {:else}
                        <span class="w-7 shrink-0" aria-hidden="true"></span>
                      {/if}
                      <div class="grow min-w-0">
                        <div class="{r.checked_at ? 'text-cold-light line-through' : 'text-white'}">
                          {label(r)}
                          {#if r.kind === 'role'}
                            <span class="text-[0.6rem] uppercase tracking-wide px-1.5 py-0.5 ml-1 rounded-full border border-cold-light/40 text-cold-light">Rol</span>
                          {/if}
                          {#if r.assigned_label}
                            <span class="text-[0.6rem] uppercase tracking-wide px-1.5 py-0.5 ml-1 rounded-full {r.confirmed_at ? 'bg-green-600 text-white' : 'border border-yellow/50 text-yellow'}">
                              {r.confirmed_at ? 'Confirmado' : 'Sin confirmar'}
                            </span>
                          {/if}
                        </div>
                        <!-- In full mode the assignee normally lives inside the
                             select, so a collapsed row would say nothing about
                             who has it. Seeing that at a glance IS the list's
                             job, and one line of small text is not the clutter
                             being removed — two dropdowns are. -->
                        {#if r.assigned_label && (mode === 'checklist' || !editing.has(r.id))}
                          <div class="text-xs text-cold-light">{r.assigned_label}</div>
                        {/if}
                        {#if r.notes}<div class="text-xs text-cold-light">{r.notes}</div>{/if}
                      </div>
                      <!-- Down/Up, never Right. A right chevron is this app's
                           NAVIGATION affordance (PartyListItem, the bands list),
                           so reusing it here would read as "go to" rather than
                           "open". Down = there is more below, the accordion
                           convention, and unambiguous next to that.
                           This is the ONLY control on a collapsed row's right
                           edge, and nothing ever replaces it — see the removal
                           note in the editors block below. -->
                      {#if mode === 'full' && r.source !== 'unassigned'}
                        <button type="button" on:click={() => toggleExpanded(r.id)}
                          aria-expanded={editing.has(r.id)}
                          aria-label="{editing.has(r.id) ? 'Ocultar' : 'Editar'} de dónde sale {label(r)}"
                          class="text-cold-light/60 hover:text-cold-light p-1 shrink-0">
                          {#if editing.has(r.id)}<ChevronUp size={16} />{:else}<ChevronDown size={16} />{/if}
                        </button>
                      {/if}
                    </div>

                    {#if mode === 'full' && editing.has(r.id)}
                    <div class="flex items-center gap-2 flex-wrap">
                      <!-- Once it is ticked off it is HERE: changing who was
                           bringing it after the fact only corrupts the record.
                           Untick to edit — the tick is the escape hatch. -->
                      <select
                        value={r.source}
                        disabled={!!r.checked_at}
                        on:change={(e) => setSource(r, (e.currentTarget as HTMLSelectElement).value as Requirement['source'])}
                        aria-label="¿De dónde sale {label(r)}?"
                        class="text-xs p-1 rounded-lg disabled:opacity-50"
                      >
                        {#each SOURCE_ORDER as s}<option value={s}>{SOURCE_LABEL[s]}</option>{/each}
                      </select>

                      <!-- A venue-provided item has no assignee: the local
                           supplies it, there is no person to chase. -->
                      {#if r.source === 'venue'}
                        <span class="text-xs text-cold-light/60">Lo pone el local</span>
                      {:else if namingFor === r.id}
                        <!-- Someone with no account. A typed name is a weaker
                             commitment than a confirmed user — there is nobody to
                             notify — so the badge stays "Sin confirmar". -->
                        <input type="text" bind:value={typedName} maxlength="60" placeholder="Nombre"
                          aria-label="Nombre de quien lo trae" class="text-xs p-1 rounded-lg w-32"
                          on:keydown={(e) => e.key === 'Enter' && saveTypedName(r)} />
                        <button type="button" on:click={() => saveTypedName(r)} class="text-cold-light hover:text-white p-1" aria-label="Guardar nombre"><Check size={15} /></button>
                        <button type="button" on:click={() => (namingFor = null)} class="text-cold-light hover:text-white p-1" aria-label="Cancelar"><X size={15} /></button>
                      {:else}
                        <select
                          value={r.assigned_user ?? (r.assigned_label ? '__other' : '')}
                          disabled={!!r.checked_at}
                          on:change={(e) => onAssignSelect(r, (e.currentTarget as HTMLSelectElement).value)}
                          aria-label="¿Quién lo trae? {label(r)}"
                          class="text-xs p-1 rounded-lg max-w-[10rem] disabled:opacity-50"
                        >
                          <option value="">Sin asignar</option>
                          {#each people as p}<option value={p.id}>{p.nickname}</option>{/each}
                          {#if r.assigned_user && !people.some((p) => p.id === r.assigned_user)}
                            <!-- Assigned from a PAST toque (the Stage 4 suggestion)
                                 and not on this one's roster. Without this option
                                 the select renders with nothing selected, and the
                                 next touch would silently reassign away from a
                                 person the organizer never saw. -->
                            <option value={r.assigned_user}>{r.assigned_label ?? 'Alguien'}</option>
                          {/if}
                          <option value="__other">{r.assigned_label && !r.assigned_user ? r.assigned_label : 'Otra persona…'}</option>
                        </select>
                        {#if !r.assigned_label}
                          <UserPlus size={14} class="text-cold-light/50" />
                        {/if}
                      {/if}

                      <!-- Removal lives HERE, not on the header row. Putting it
                           beside the chevron meant it appeared at the exact
                           pixel the chevron had occupied — measured: same x,
                           same 24px — so a second tap after expanding landed on
                           an unconfirmed delete. Down here nothing ever takes
                           the place of something you just pressed. -->
                      <span class="ml-auto flex items-center gap-1 shrink-0">
                        {#if confirmingRemove === r.id}
                          <span class="text-xs text-warm-base">¿Quitar?</span>
                          <button type="button" on:click={() => remove(r)}
                            aria-label="Confirmar quitar {label(r)}"
                            class="text-warm-base hover:text-red-400 p-1"><Check size={16} /></button>
                          <button type="button" on:click={() => (confirmingRemove = null)}
                            aria-label="Cancelar"
                            class="text-cold-light hover:text-white p-1"><X size={16} /></button>
                        {:else}
                          <button type="button" on:click={() => (confirmingRemove = r.id)}
                            aria-label="Quitar {label(r)}"
                            class="text-warm-base/70 hover:text-warm-base p-1"><Trash2 size={16} /></button>
                        {/if}
                      </span>
                    </div>
                    {/if}
                  </li>
                {/each}
              </ul>
            </li>
          {/each}
        </ul>

        {#if mode === 'full'}
        <div class="flex flex-wrap gap-2 mt-3">
          {#if !adding}
            <button type="button" on:click={openAdd}
              class="bg-cold-base text-white rounded-lg px-4 py-2 inline-flex items-center gap-2 text-sm">
              <Plus size={16} /> Agregar equipo o rol
            </button>
          {/if}
          {#if seedable.length}
            <button type="button" on:click={seedFromVenue} disabled={busy}
              class="border border-cold-light/40 text-cold-light hover:border-cold-light rounded-lg px-4 py-2 inline-flex items-center gap-2 text-sm disabled:opacity-60">
              <Download size={16} /> Traer el equipo del local ({seedable.length})
            </button>
          {/if}
        </div>
        {/if}

        {#if adding}
          <div class="mt-3 p-3 bg-base-900 rounded-lg flex flex-col gap-2">
            <div class="flex items-center justify-between">
              <span class="text-cold-light text-sm">¿Qué hace falta?</span>
              <button type="button" on:click={() => { adding = false; resetForm(); }} aria-label="Cancelar"
                class="text-cold-light hover:text-white p-1"><X size={16} /></button>
            </div>
            <div class="flex gap-2">
              <select bind:value={formKind} on:change={() => { formItemId = ''; lastTime = null; useLastTime = false; }} aria-label="Tipo" class="p-2 rounded-lg text-sm">
                <option value="equipment">Equipo</option>
                <option value="role">Rol</option>
              </select>
              <select bind:value={formItemId} on:change={() => lookupLastTime(formKind, formItemId)}
                aria-label="Qué" class="p-2 rounded-lg text-sm grow min-w-0">
                <option value="">Selecciona…</option>
                {#if formKind === 'equipment'}
                  {#each Object.entries(equipmentByCategory) as [category, items]}
                    <optgroup label={category}>
                      {#each items as e}<option value={String(e.id)}>{e.name}</option>{/each}
                    </optgroup>
                  {/each}
                {:else}
                  {#each roles as r}<option value={String(r.id)}>{r.name}</option>{/each}
                {/if}
              </select>
              <!-- Only once an item is chosen: before that formQuantity is ''
                   and a stepper reading "1" would claim a quantity nobody set. -->
              {#if formKind === 'equipment' && formItemId}
                <div class="inline-flex items-center rounded-lg border border-cold-light/30 overflow-hidden shrink-0">
                  <button type="button" on:click={() => stepFormQuantity(-1)}
                    disabled={(Number(formQuantity) || 1) <= 1}
                    aria-label="Menos cantidad"
                    class="px-3 py-1 text-lg leading-none text-cold-light hover:bg-base-950 disabled:opacity-40 disabled:hover:bg-transparent">−</button>
                  <span class="px-2 min-w-[2.5ch] text-center text-white text-sm tabular-nums" aria-live="polite">{Number(formQuantity) || 1}</span>
                  <button type="button" on:click={() => stepFormQuantity(1)}
                    aria-label="Más cantidad"
                    class="px-3 py-1 text-lg leading-none text-cold-light hover:bg-base-950">+</button>
                </div>
              {/if}
            </div>
            <select bind:value={formSource} aria-label="¿De dónde sale?" class="p-2 rounded-lg text-sm">
              {#each SOURCE_ORDER as s}<option value={s}>{SOURCE_LABEL[s]}</option>{/each}
            </select>
            <input type="text" bind:value={formNotes} maxlength="200" placeholder="Nota (opcional)"
              aria-label="Nota" class="p-2 rounded-lg text-sm" />

            {#if lastTime}
              <!-- The record, read back where it is actually useful (#95 Stage 4).
                   A suggestion, never an automatic assignment: the organizer is
                   the one who knows whether it holds this time. -->
              <label class="flex items-start gap-2 text-sm text-cold-light cursor-pointer">
                <input type="checkbox" bind:checked={useLastTime} class="mt-0.5" />
                <span class="inline-flex items-center gap-1.5">
                  <History size={14} class="shrink-0" />
                  La última vez lo trajo <span class="text-white">{lastTime.assigned_label}</span>. ¿Otra vez?
                </span>
              </label>
            {/if}
            <button type="button" on:click={addRequirement} disabled={!formItemId || busy}
              class="bg-cold-base text-white rounded-lg px-4 py-2 text-sm disabled:opacity-50">Agregar</button>
          </div>
        {/if}
      {/if}
    {/if}
  </div>
{/if}
