<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import AutocompleteInput from '$lib/components/AutocompleteInput.svelte';
  import { normalizeText } from '$lib/sanitize';
  export let submitting = false;
  export let initialName = '';
  export let initialAddress = '';
  export let initialContactName = '';
  export let initialContact = '';
  export let initialWhatsapp = '';
  export let initialInstagram = '';
  export let initialVenueType = '';
  export let venueTypes: any[] = [];
  export let initialAllowsParties = true;
  export let initialAllowsRehearsals = false;
  export let userId: string | null = null;
  export let isAuthenticated = false;
  export let initialAdmins: string[] = [];
  // Venue profile (#30)
  export let equipmentOptions: any[] = [];
  export let initialEquipment: { equipment_id: number; quantity: number | null; notes: string | null }[] = [];
  export let initialRequiresApproval = true;
  export let initialEngagementModel = '';
  export let initialEngagementNotes = '';
  export let initialMinAge: number | null = null;
  export let initialCurfew = '';
  export let initialCapacity: number | null = null;
  export let initialHouseRules = '';

  const dispatch = createEventDispatcher();

  const engagementModels = [
    { value: 'free', label: 'Sin costo (gratis)' },
    { value: 'door_split', label: 'Reparto de taquilla' },
    { value: 'guarantee', label: 'Pago fijo (garantía)' },
    { value: 'pay_to_play', label: 'Cuota para tocar' },
    { value: 'tips', label: 'Propinas' },
    { value: 'bar_minimum', label: 'Consumo mínimo' },
    { value: 'other', label: 'Otro' }
  ];

  let name = initialName;
  let address = initialAddress;
  let contactName = initialContactName;
  let contact = initialContact;
  let whatsapp = initialWhatsapp;
  let instagram = initialInstagram;
  let selectedVenueType = initialVenueType;
  let allowsParties = initialAllowsParties;
  let allowsRehearsals = initialAllowsRehearsals;
  let admins: any[] = [];
  let userOptions: any[] = [];
  let adminInput = '';
  let filteredOptions: any[] = [];
  // Venue profile state
  // Editable equipment rows built from the lookup, pre-filled from the venue's
  // current equipment (id → selected + quantity + description).
  let equipmentRows: { id: number; name: string; selected: boolean; quantity: number | null; notes: string }[] = [];
  let equipmentBuilt = false;
  $: if (!equipmentBuilt && equipmentOptions.length) {
    equipmentBuilt = true;
    const byId = new Map((initialEquipment ?? []).map((e) => [e.equipment_id, e]));
    equipmentRows = equipmentOptions.map((opt) => {
      const cur = byId.get(opt.id);
      return {
        id: opt.id,
        name: opt.name,
        selected: !!cur,
        quantity: cur?.quantity ?? 1, // default to 1; stepper enforces min 1
        notes: cur?.notes ?? ''
      };
    });
  }
  let requiresApproval = initialRequiresApproval;
  let engagementModel = initialEngagementModel;
  let engagementNotes = initialEngagementNotes;
  let minAge: number | null = initialMinAge;
  let curfew = initialCurfew;
  let capacity: number | null = initialCapacity;
  let houseRules = initialHouseRules;

  // Popular equipment descriptions per equipment type (#49), so venues converge
  // on consistent gear names. Fetched across venues (venue_equipment.notes is
  // world-readable) and ranked by frequency; AutocompleteInput filters as you type.
  let notesSuggestions: Record<number, string[]> = {};

  onMount(async () => {
    // Fetch all users for autocomplete
    const { data: users } = await supabase.from('profile').select('id, nickname');
    userOptions = users ?? [];
    // Pre-fill admins if editing
    if (initialAdmins && initialAdmins.length > 0) {
      admins = userOptions.filter(u => initialAdmins.includes(u.id));
    }
    // Build the description-suggestion pool per equipment: real usage ranked by
    // frequency first, then the curated catalog (#49) fills the rest.
    const [{ data: notesData }, { data: sugData }] = await Promise.all([
      supabase.from('venue_equipment').select('equipment_id, notes').not('notes', 'is', null),
      supabase.from('equipment_suggestion').select('equipment_id, label')
    ]);
    const counts: Record<number, Record<string, number>> = {};
    for (const r of notesData ?? []) {
      const n = (r.notes ?? '').trim();
      if (!n || r.equipment_id == null) continue;
      (counts[r.equipment_id] ??= {})[n] = (counts[r.equipment_id][n] ?? 0) + 1;
    }
    const curated: Record<number, string[]> = {};
    for (const s of sugData ?? []) (curated[s.equipment_id] ??= []).push(s.label);
    const out: Record<number, string[]> = {};
    const eids = new Set<number>([...Object.keys(counts), ...Object.keys(curated)].map(Number));
    for (const eid of eids) {
      const realAll = Object.entries(counts[eid] ?? {}).sort((a, b) => b[1] - a[1]).map(([n]) => n);
      const realSet = new Set(realAll);
      // Top real usage by frequency, then the whole curated catalog for this type.
      const extra = (curated[eid] ?? []).filter((l) => !realSet.has(l));
      out[eid] = [...realAll.slice(0, 8), ...extra];
    }
    notesSuggestions = out;
  });

  function toggleEquipment(row: { selected: boolean; quantity: number | null }) {
    row.selected = !row.selected;
    if (row.selected && (row.quantity ?? 0) < 1) row.quantity = 1;
    equipmentRows = equipmentRows; // nudge reactivity
  }

  function stepQuantity(row: { quantity: number | null }, delta: number) {
    row.quantity = Math.max(1, (row.quantity ?? 1) + delta);
    equipmentRows = equipmentRows;
  }

  function handleAdminInput(e: Event) {
    adminInput = (e.target as HTMLInputElement).value;
    filteredOptions = userOptions.filter(u =>
      u.nickname.toLowerCase().includes(adminInput.toLowerCase()) && !admins.some(a => a.id === u.id)
    );
  }

  function addAdmin(user: any) {
    admins = [...admins, user];
    adminInput = '';
    filteredOptions = [];
  }

  function removeAdmin(userId: string) {
    admins = admins.filter(a => a.id !== userId);
  }

  function handleSubmit() {
    if (!name || !address || !contactName || !contact || !selectedVenueType) {
      dispatch('error', 'Todos los campos son obligatorios.');
      return;
    }
    dispatch('submit', {
      name: normalizeText(name, 120),
      address: normalizeText(address, 200),
      contactName: normalizeText(contactName, 120),
      contact: normalizeText(contact, 200),
      whatsapp: normalizeText(whatsapp, 40),
      instagram: normalizeText(instagram, 60),
      venueType: selectedVenueType,
      allowsParties,
      allowsRehearsals,
      admins: admins.map(a => a.id),
      equipment: equipmentRows.filter((r) => r.selected).map((r) => ({
        equipment_id: r.id,
        quantity: r.quantity === null || r.quantity === undefined || (r.quantity as any) === '' ? null : Number(r.quantity),
        notes: r.notes && r.notes.trim() ? r.notes.trim() : null
      })),
      requiresApproval,
      engagementModel: engagementModel || null,
      engagementNotes: normalizeText(engagementNotes, 1000) || null,
      minAge: minAge === null || minAge === undefined || (minAge as any) === '' ? null : Number(minAge),
      curfew: curfew || null,
      capacity: capacity === null || capacity === undefined || (capacity as any) === '' ? null : Number(capacity),
      houseRules: normalizeText(houseRules, 2000) || null
    });
  }

  function validateWhatsapp(event: Event) {
    const value = (event.target as HTMLInputElement).value;
    if (value && !/^\+?[1-9]\d{1,14}$/.test(value.replace(/\s/g, ''))) {
      setInvalid(event, 'Ingresa un número de WhatsApp válido (ej: +5491234567890)');
    } else {
      clearInvalid(event);
    }
  }

  function validateInstagram(event: Event) {
    const value = (event.target as HTMLInputElement).value;
    if (value && !/^[a-zA-Z0-9._]{1,30}$/.test(value)) {
      setInvalid(event, 'Ingresa un usuario de Instagram válido (solo letras, números, puntos y guiones bajos)');
    } else {
      clearInvalid(event);
    }
  }

  function setInvalid(event: Event, errorMessage: string) {
    (event.target as HTMLInputElement).setCustomValidity(errorMessage);
  }
  function clearInvalid(event: Event) {
    (event.target as HTMLInputElement).setCustomValidity('');
  }
</script>
<form on:submit|preventDefault={handleSubmit}>
  <div class="flex flex-col w-full p-4 mb-4">
    <label for="name" class="mb-1">Nombre del Local</label>
    <input id="name" type="text" bind:value={name} required class="p-2 border rounded-lg mb-2" on:invalid={(event) => setInvalid(event, 'Por favor ingresa el nombre del local')} on:input={clearInvalid} />
    <label for="address" class="mb-1">Dirección</label>
    <input id="address" type="text" bind:value={address} required class="p-2 border rounded-lg mb-2" on:invalid={(event) => setInvalid(event, 'Por favor ingresa la dirección del local')} on:input={clearInvalid} />
    <label for="contact_name" class="mb-1">Persona de contacto</label>
    <input id="contact_name" type="text" bind:value={contactName} required class="p-2 border rounded-lg mb-2" on:invalid={(event) => setInvalid(event, 'Por favor ingresa el nombre de la persona de contacto')} on:input={clearInvalid} />
    <label for="contact" class="mb-1">Info de contacto</label>
    <input id="contact" type="text" bind:value={contact} required class="p-2 border rounded-lg mb-2" placeholder="telefono, correo, instagram" on:invalid={(event) => setInvalid(event, 'Por favor ingresa la información de contacto')} on:input={clearInvalid} />
    <label for="whatsapp" class="mb-1">WhatsApp (opcional)</label>
    <input id="whatsapp" type="text" bind:value={whatsapp} class="p-2 border rounded-lg mb-2" placeholder="+5491234567890" on:blur={validateWhatsapp} on:input={clearInvalid} />
    <label for="instagram" class="mb-1">Instagram (opcional)</label>
    <input id="instagram" type="text" bind:value={instagram} class="p-2 border rounded-lg mb-2" placeholder="usuario_instagram" on:blur={validateInstagram} on:input={clearInvalid} />
    <label for="venue_type" class="mb-1">Tipo de Local</label>
    <select id="venue_type" bind:value={selectedVenueType} class="p-2 border rounded-lg" required on:invalid={(event) => setInvalid(event, 'Por favor selecciona un tipo de local')} on:input={clearInvalid}>
      {#each venueTypes as type}
        <option value={type.id}>{type.name}</option>
      {/each}
    </select>
    <div class="flex items-center mb-4 mt-4">
      <input id="allows_parties" type="checkbox" bind:checked={allowsParties} class="mr-2" />
      <label for="allows_parties" class="cursor-pointer">Permite fiestas</label>
    </div>
    <div class="flex items-center mb-4">
      <input id="allows_rehearsals" type="checkbox" bind:checked={allowsRehearsals} class="mr-2" />
      <label for="allows_rehearsals" class="cursor-pointer">Permite ensayos</label>
    </div>

    <!-- Administradores del local -->
    <h3 class="text-lg text-yellow mt-4 mb-2">Administradores del local</h3>
    <div class="mb-2">
      <input id="venue_admins" type="text" bind:value={adminInput} on:input={handleAdminInput} placeholder="Buscar usuario..." aria-label="Buscar administrador" class="p-2 border rounded-lg w-full" />
      {#if adminInput && filteredOptions.length > 0}
        <ul class="bg-base-950 border rounded-lg shadow mt-1">
          {#each filteredOptions as option}
            <li class="p-2 cursor-pointer hover:bg-base-900" on:click={() => addAdmin(option)}>{option.nickname}</li>
          {/each}
        </ul>
      {/if}
      <div class="flex flex-wrap gap-2 mt-2">
        {#each admins as admin}
          <span class="bg-cold-base text-white rounded-lg px-2 py-1 flex items-center gap-1">
            {admin.nickname}
            <button type="button" class="ml-1 text-yellow" on:click={() => removeAdmin(admin.id)}>✕</button>
          </span>
        {/each}
      </div>
    </div>

    <!-- Equipo / backline (#30) -->
    <h3 class="text-lg text-yellow mt-4 mb-2">Equipo disponible</h3>
    <div class="flex flex-col gap-2 mb-2">
      {#each equipmentRows as row (row.id)}
        <div class="{row.selected ? 'bg-base-900 rounded-lg p-3' : ''}">
          <button
            type="button"
            on:click={() => toggleEquipment(row)}
            aria-pressed={row.selected}
            class="px-3 py-1 rounded-full text-sm transition border {row.selected
              ? 'bg-cold-base text-white border-cold-base'
              : 'bg-base-900 text-cold-light border-base-900 hover:border-cold-light'}"
          >
            {row.name}
          </button>
          {#if row.selected}
            <div class="mt-3 flex flex-col gap-2">
              <div class="flex flex-row items-center gap-3">
                <span class="text-sm text-cold-light">Cantidad</span>
                <div class="inline-flex items-center rounded-lg border overflow-hidden">
                  <button type="button" on:click={() => stepQuantity(row, -1)} disabled={(row.quantity ?? 1) <= 1}
                    class="px-3 py-1 text-lg leading-none text-cold-light hover:bg-base-950 disabled:opacity-40 disabled:hover:bg-transparent"
                    aria-label="Disminuir cantidad de {row.name}">−</button>
                  <span class="px-3 min-w-[2.5ch] text-center text-white" aria-live="polite">{row.quantity ?? 1}</span>
                  <button type="button" on:click={() => stepQuantity(row, 1)}
                    class="px-3 py-1 text-lg leading-none text-cold-light hover:bg-base-950"
                    aria-label="Aumentar cantidad de {row.name}">+</button>
                </div>
              </div>
              <AutocompleteInput
                bind:value={row.notes}
                suggestions={notesSuggestions[row.id] ?? []}
                placeholder="Marca, modelo, tamaño..."
                maxlength={200}
                ariaLabel={`Descripción de ${row.name}`}
              />
            </div>
          {/if}
        </div>
      {/each}
    </div>

    <!-- Modelo económico (#30) -->
    <h3 class="text-lg text-yellow mt-4 mb-2">Modelo económico</h3>
    <label for="engagement_model" class="mb-1">¿Qué condiciones económicas pone el local para tocar?</label>
    <select id="engagement_model" bind:value={engagementModel} class="p-2 border rounded-lg mb-2">
      <option value="">Sin especificar</option>
      {#each engagementModels as m}
        <option value={m.value}>{m.label}</option>
      {/each}
    </select>
    <label for="engagement_notes" class="mb-1">Detalles (opcional)</label>
    <textarea id="engagement_notes" bind:value={engagementNotes} rows="2" class="p-2 border rounded-lg mb-2" placeholder="Cuota de reserva, % del reparto, consumo mínimo..."></textarea>

    <!-- Restricciones (#30) -->
    <h3 class="text-lg text-yellow mt-4 mb-2">Restricciones</h3>
    <label for="min_age" class="mb-1">Edad mínima (0 = todo público)</label>
    <input id="min_age" type="number" min="0" bind:value={minAge} class="p-2 border rounded-lg mb-2" placeholder="18" />
    <label for="curfew" class="mb-1">Hora límite de música</label>
    <input id="curfew" type="time" bind:value={curfew} class="p-2 border rounded-lg mb-2" />
    <label for="capacity" class="mb-1">Aforo</label>
    <input id="capacity" type="number" min="0" bind:value={capacity} class="p-2 border rounded-lg mb-2" placeholder="80" />
    <label for="house_rules" class="mb-1">Reglas de la casa (opcional)</label>
    <textarea id="house_rules" bind:value={houseRules} rows="2" class="p-2 border rounded-lg mb-2" placeholder="Géneros, solo covers, carga y descarga, humo..."></textarea>

    <!-- Aprobación (#30) -->
    <div class="flex items-start mb-4 mt-4">
      <input id="requires_approval" type="checkbox" bind:checked={requiresApproval} class="mr-2 mt-1" />
      <label for="requires_approval" class="cursor-pointer">
        Requiere aprobación del local para agendar un toque
        <span class="block text-sm text-cold-light">Si está activo, los toques quedan pendientes hasta que un admin del local los apruebe.</span>
      </label>
    </div>
  </div>
  <button class="bg-cold-base text-white rounded-lg mx-4 mb-8 p-4 px-6" type="submit" disabled={submitting}>
    {submitting ? 'Guardando...' : 'Guardar Local'}
  </button>
</form>
