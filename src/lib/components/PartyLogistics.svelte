<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { Plus, Trash2, AlertTriangle, Check, Download, X, UserPlus, Square, CheckSquare } from 'lucide-svelte';
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

  let equipment: { id: number; name: string; category: string | null }[] = [];
  let roles: { id: number; name: string }[] = [];
  let catalogueLoaded = false;
  let venueEquipment: { equipment_id: number; quantity: number | null; notes: string | null }[] = [];

  let adding = false;
  let formKind: 'equipment' | 'role' = 'equipment';
  let formItemId = '';
  let formQuantity = '';
  let formSource: Requirement['source'] = 'unassigned';
  let formNotes = '';

  // Which row is showing its "someone not on the app" text field.
  let namingFor: number | null = null;
  let typedName = '';

  const SOURCE_LABEL: Record<Requirement['source'], string> = {
    unassigned: 'Sin resolver',
    venue: 'Del local',
    organizer: 'Lo llevas tú',
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
      supabase.from('equipment').select('id, name, category').order('id'),
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
  function resetForm() { formItemId = ''; formQuantity = ''; formSource = 'unassigned'; formNotes = ''; }

  async function addRequirement() {
    if (!formItemId || busy) return;
    busy = true;
    const { data, error } = await supabase
      .from('party_requirement')
      .insert({
        party_id: partyId,
        kind: formKind,
        source: formSource,
        notes: formNotes.trim() || null,
        equipment_id: formKind === 'equipment' ? Number(formItemId) : null,
        role_id: formKind === 'role' ? Number(formItemId) : null,
        quantity: formKind === 'equipment' && formQuantity ? Number(formQuantity) : null
      } as any)
      .select(COLS);
    busy = false;
    if (error) { reportError(error); return; }
    requirements = [...requirements, ...((data ?? []) as unknown as Requirement[])];
    resetForm();
    adding = false;
  }

  async function setSource(r: Requirement, source: Requirement['source']) {
    const confirmed_at = source === 'venue' ? new Date().toISOString() : r.confirmed_at;
    const { error } = await supabase.from('party_requirement').update({ source, confirmed_at }).eq('id', r.id);
    if (error) { reportError(error); return; }
    patch(r.id, { source, confirmed_at });
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
    const person = people.find((p) => p.id === value);
    assign(r, value, person?.nickname ?? null);
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
                        {#if r.assigned_label && mode === 'checklist'}
                          <div class="text-xs text-cold-light">{r.assigned_label}</div>
                        {/if}
                        {#if r.notes}<div class="text-xs text-cold-light">{r.notes}</div>{/if}
                      </div>
                      {#if mode === 'full'}
                      <button type="button" on:click={() => remove(r)} aria-label="Quitar {label(r)}"
                        class="text-warm-base hover:text-red-400 p-1 shrink-0"><Trash2 size={16} /></button>
                      {/if}
                    </div>

                    {#if mode === 'full'}
                    <div class="flex items-center gap-2 flex-wrap">
                      <select
                        value={r.source}
                        on:change={(e) => setSource(r, (e.currentTarget as HTMLSelectElement).value as Requirement['source'])}
                        aria-label="¿De dónde sale {label(r)}?"
                        class="text-xs p-1 rounded-lg"
                      >
                        {#each SOURCE_ORDER as s}<option value={s}>{SOURCE_LABEL[s]}</option>{/each}
                      </select>

                      {#if namingFor === r.id}
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
                          on:change={(e) => onAssignSelect(r, (e.currentTarget as HTMLSelectElement).value)}
                          aria-label="¿Quién lo trae? {label(r)}"
                          class="text-xs p-1 rounded-lg max-w-[10rem]"
                        >
                          <option value="">Sin asignar</option>
                          {#each people as p}<option value={p.id}>{p.nickname}</option>{/each}
                          <option value="__other">{r.assigned_label && !r.assigned_user ? r.assigned_label : 'Otra persona…'}</option>
                        </select>
                        {#if !r.assigned_label}
                          <UserPlus size={14} class="text-cold-light/50" />
                        {/if}
                      {/if}
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
              <select bind:value={formKind} on:change={() => (formItemId = '')} aria-label="Tipo" class="p-2 rounded-lg text-sm">
                <option value="equipment">Equipo</option>
                <option value="role">Rol</option>
              </select>
              <select bind:value={formItemId} aria-label="Qué" class="p-2 rounded-lg text-sm grow min-w-0">
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
              {#if formKind === 'equipment'}
                <input type="number" min="1" bind:value={formQuantity} placeholder="Cant."
                  aria-label="Cantidad" class="p-2 rounded-lg text-sm w-20" />
              {/if}
            </div>
            <select bind:value={formSource} aria-label="¿De dónde sale?" class="p-2 rounded-lg text-sm">
              {#each SOURCE_ORDER as s}<option value={s}>{SOURCE_LABEL[s]}</option>{/each}
            </select>
            <input type="text" bind:value={formNotes} maxlength="200" placeholder="Nota (opcional)"
              aria-label="Nota" class="p-2 rounded-lg text-sm" />
            <button type="button" on:click={addRequirement} disabled={!formItemId || busy}
              class="bg-cold-base text-white rounded-lg px-4 py-2 text-sm disabled:opacity-50">Agregar</button>
          </div>
        {/if}
      {/if}
    {/if}
  </div>
{/if}
