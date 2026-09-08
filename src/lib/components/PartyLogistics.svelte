<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { Plus, Trash2, AlertTriangle, Check, Download, X } from 'lucide-svelte';
  import { reportError, toastSuccess, toastInfo } from '$lib/stores/toasts';

  // Event logistics, Stage 1 (#95). What this toque needs and where each piece
  // is coming from. The valuable output is not the inventory — it is the GAP
  // LIST, which is why the counter is the headline and not a footnote.
  export let partyId: number;
  export let venueId: number | null = null;
  // Admin-only surface. Non-admins fetch nothing at all, so the common case
  // (someone just looking at a toque) pays nothing for this feature.
  export let canAdmin = false;

  type Requirement = {
    id: number;
    kind: 'equipment' | 'role';
    equipment_id: number | null;
    role_id: number | null;
    quantity: number | null;
    source: 'unassigned' | 'venue' | 'organizer' | 'performer' | 'external';
    notes: string | null;
    confirmed_at: string | null;
  };

  let requirements: Requirement[] = [];
  let loaded = false;
  let busy = false;

  // Catalogues are only needed once the organizer opens the add form, so they
  // are fetched on demand rather than on every party-detail load (#84).
  let equipment: { id: number; name: string; category: string | null }[] = [];
  let roles: { id: number; name: string }[] = [];
  let catalogueLoaded = false;

  // What the venue says it has, for the seed action.
  let venueEquipment: { equipment_id: number; quantity: number | null; notes: string | null }[] = [];

  let adding = false;
  let formKind: 'equipment' | 'role' = 'equipment';
  let formItemId = '';
  let formQuantity = '';
  let formSource: Requirement['source'] = 'unassigned';
  let formNotes = '';

  const SOURCE_LABEL: Record<Requirement['source'], string> = {
    unassigned: 'Sin resolver',
    venue: 'Del local',
    organizer: 'Lo llevas tú',
    performer: 'Lo trae un músico',
    external: 'Alquilado o externo'
  };
  // Unresolved first: the whole point is that the gaps are the thing you act on.
  const SOURCE_ORDER: Requirement['source'][] = ['unassigned', 'venue', 'organizer', 'performer', 'external'];

  onMount(async () => {
    if (!canAdmin) return;
    // One wave: the rows plus what the venue offers (needed to decide whether to
    // show the seed action at all).
    const [reqRes, veRes] = await Promise.all([
      supabase
        .from('party_requirement')
        .select('id, kind, equipment_id, role_id, quantity, source, notes, confirmed_at')
        .eq('party_id', partyId)
        .order('id', { ascending: true }),
      venueId
        ? supabase.from('venue_equipment').select('equipment_id, quantity, notes').eq('venue_id', venueId)
        : Promise.resolve({ data: [] as any[] })
    ]);
    requirements = (reqRes.data ?? []) as Requirement[];
    venueEquipment = veRes.data ?? [];
    // Names are needed to render the existing rows, so if there are any we do
    // need the catalogue after all.
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
    roles = (roleRes.data ?? []) as any[];
    catalogueLoaded = true;
  }

  // Derived maps, not helper functions: Svelte legacy mode tracks dependencies
  // by NAME, so a function reading `equipment` internally would leave the
  // template stale when the catalogue lands.
  $: equipmentName = Object.fromEntries(equipment.map((e) => [e.id, e.name]));
  $: roleName = Object.fromEntries(roles.map((r) => [r.id, r.name]));
  $: equipmentByCategory = equipment.reduce((acc: Record<string, typeof equipment>, e) => {
    const key = e.category ?? 'otros';
    (acc[key] ??= []).push(e);
    return acc;
  }, {});

  $: gaps = requirements.filter((r) => r.source === 'unassigned').length;
  $: grouped = SOURCE_ORDER.map((source) => ({
    source,
    label: SOURCE_LABEL[source],
    items: requirements.filter((r) => r.source === source)
  })).filter((g) => g.items.length);

  // Equipment the venue has that is not on the list yet — the seed action is
  // only worth offering when it would actually add something.
  $: alreadyListed = new Set(requirements.filter((r) => r.equipment_id).map((r) => r.equipment_id));
  $: seedable = venueEquipment.filter((ve) => !alreadyListed.has(ve.equipment_id));

  function label(r: Requirement) {
    const name = r.kind === 'equipment' ? equipmentName[r.equipment_id!] : roleName[r.role_id!];
    if (!name) return '…';
    return r.quantity && r.quantity > 1 ? `${name} ×${r.quantity}` : name;
  }

  async function openAdd() {
    adding = true;
    await loadCatalogue();
  }

  function resetForm() {
    formItemId = '';
    formQuantity = '';
    formSource = 'unassigned';
    formNotes = '';
  }

  async function addRequirement() {
    if (!formItemId || busy) return;
    busy = true;
    const row: any = {
      party_id: partyId,
      kind: formKind,
      source: formSource,
      notes: formNotes.trim() || null,
      equipment_id: formKind === 'equipment' ? Number(formItemId) : null,
      role_id: formKind === 'role' ? Number(formItemId) : null,
      quantity: formKind === 'equipment' && formQuantity ? Number(formQuantity) : null
    };
    const { data, error } = await supabase
      .from('party_requirement')
      .insert(row)
      .select('id, kind, equipment_id, role_id, quantity, source, notes, confirmed_at');
    busy = false;
    if (error) { reportError(error); return; }
    requirements = [...requirements, ...((data ?? []) as Requirement[])];
    resetForm();
    adding = false;
  }

  async function setSource(r: Requirement, source: Requirement['source']) {
    // Moving something OFF unassigned is the organizer saying they've sorted it;
    // moving it back re-opens the gap. `venue` is pre-confirmed because the
    // venue's own profile already declares it.
    const confirmed_at = source === 'venue' ? new Date().toISOString() : r.confirmed_at;
    const { error } = await supabase
      .from('party_requirement')
      .update({ source, confirmed_at })
      .eq('id', r.id);
    if (error) { reportError(error); return; }
    requirements = requirements.map((x) => (x.id === r.id ? { ...x, source, confirmed_at } : x));
  }

  async function remove(r: Requirement) {
    const { error } = await supabase.from('party_requirement').delete().eq('id', r.id);
    if (error) { reportError(error); return; }
    requirements = requirements.filter((x) => x.id !== r.id);
  }

  // Explicit, never a trigger on venue change: an organizer's edits must not be
  // silently clobbered, and re-running it after a venue swap should be a
  // decision rather than a surprise.
  async function seedFromVenue() {
    if (!seedable.length || busy) return;
    busy = true;
    await loadCatalogue();
    const now = new Date().toISOString();
    const rows = seedable.map((ve) => ({
      party_id: partyId,
      kind: 'equipment' as const,
      equipment_id: ve.equipment_id,
      quantity: ve.quantity,
      source: 'venue' as const,
      notes: ve.notes,
      confirmed_at: now
    }));
    const { data, error } = await supabase
      .from('party_requirement')
      .insert(rows)
      .select('id, kind, equipment_id, role_id, quantity, source, notes, confirmed_at');
    busy = false;
    if (error) { reportError(error); return; }
    requirements = [...requirements, ...((data ?? []) as Requirement[])];
    toastSuccess(`${rows.length} ${rows.length === 1 ? 'equipo' : 'equipos'} del local en la lista.`);
  }
</script>

{#if canAdmin}
  <div class="mt-6">
    <div class="flex items-center justify-between mb-2">
      <h3 class="text-3xl text-white font-medium tracking-widest">LOGÍSTICA</h3>
      {#if loaded && requirements.length}
        {#if gaps}
          <!-- The nag. A list without it is just data entry. -->
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
                <li class="bg-base-900 px-3 py-2 flex items-center gap-2">
                  <div class="grow min-w-0">
                    <div class="text-white truncate">
                      {label(r)}
                      {#if r.kind === 'role'}
                        <span class="text-[0.6rem] uppercase tracking-wide px-1.5 py-0.5 ml-1 rounded-full border border-cold-light/40 text-cold-light">Rol</span>
                      {/if}
                    </div>
                    {#if r.notes}<div class="text-xs text-cold-light truncate">{r.notes}</div>{/if}
                  </div>
                  <!-- Changing the source IS the action: it is how a gap gets
                       closed, so it sits on the row rather than behind an edit. -->
                  <select
                    value={r.source}
                    on:change={(e) => setSource(r, (e.currentTarget as HTMLSelectElement).value as Requirement['source'])}
                    aria-label="¿De dónde sale {label(r)}?"
                    class="text-xs p-1 rounded-lg shrink-0 max-w-[9rem]"
                  >
                    {#each SOURCE_ORDER as s}
                      <option value={s}>{SOURCE_LABEL[s]}</option>
                    {/each}
                  </select>
                  <button type="button" on:click={() => remove(r)} aria-label="Quitar {label(r)}"
                    class="text-warm-base hover:text-red-400 p-1 shrink-0"><Trash2 size={16} /></button>
                </li>
              {/each}
            </ul>
          </li>
        {/each}
      </ul>

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
            {#each SOURCE_ORDER as s}
              <option value={s}>{SOURCE_LABEL[s]}</option>
            {/each}
          </select>

          <input type="text" bind:value={formNotes} maxlength="200" placeholder="Nota (opcional)"
            aria-label="Nota" class="p-2 rounded-lg text-sm" />

          <button type="button" on:click={addRequirement} disabled={!formItemId || busy}
            class="bg-cold-base text-white rounded-lg px-4 py-2 text-sm disabled:opacity-50">
            Agregar
          </button>
        </div>
      {/if}
    {/if}
  </div>
{/if}
