<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
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
    { value: 'free', label: 'Gratis / sin pago' },
    { value: 'door_split', label: 'Reparto de taquilla' },
    { value: 'guarantee', label: 'Garantía fija' },
    { value: 'pay_to_play', label: 'Pago por tocar' },
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
        quantity: cur?.quantity ?? null,
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

  onMount(async () => {
    // Fetch all users for autocomplete
    const { data: users } = await supabase.from('profile').select('id, nickname');
    userOptions = users ?? [];
    // Pre-fill admins if editing
    if (initialAdmins && initialAdmins.length > 0) {
      admins = userOptions.filter(u => initialAdmins.includes(u.id));
    }
  });

  function toggleEquipment(row: { selected: boolean }) {
    row.selected = !row.selected;
    equipmentRows = equipmentRows; // nudge reactivity
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
      name,
      address,
      contactName,
      contact,
      whatsapp,
      instagram,
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
      engagementNotes: engagementNotes || null,
      minAge: minAge === null || minAge === undefined || (minAge as any) === '' ? null : Number(minAge),
      curfew: curfew || null,
      capacity: capacity === null || capacity === undefined || (capacity as any) === '' ? null : Number(capacity),
      houseRules: houseRules || null
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
  <div class="flex flex-col w-3/4 p-5 mb-4">
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
            <div class="flex flex-row gap-2 mt-2">
              <input type="number" min="1" bind:value={row.quantity} placeholder="Cant." class="p-2 border rounded-lg w-20" aria-label="Cantidad de {row.name}" />
              <input type="text" bind:value={row.notes} placeholder="Marca, modelo, tamaño..." class="p-2 border rounded-lg flex-1" aria-label="Descripción de {row.name}" />
            </div>
          {/if}
        </div>
      {/each}
    </div>

    <!-- Modelo de pago (#30) -->
    <h3 class="text-lg text-yellow mt-4 mb-2">Modelo de pago</h3>
    <label for="engagement_model" class="mb-1">¿Cómo se le paga a los músicos?</label>
    <select id="engagement_model" bind:value={engagementModel} class="p-2 border rounded-lg mb-2">
      <option value="">Sin especificar</option>
      {#each engagementModels as m}
        <option value={m.value}>{m.label}</option>
      {/each}
    </select>
    <label for="engagement_notes" class="mb-1">Detalles del pago (opcional)</label>
    <textarea id="engagement_notes" bind:value={engagementNotes} rows="2" class="p-2 border rounded-lg mb-2" placeholder="Monto de la cover, % del reparto, mínimos..."></textarea>

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

    <label for="venue_admins" class="mb-1 mt-4">Administradores del local</label>
    <div class="mb-2">
      <input id="venue_admins" type="text" bind:value={adminInput} on:input={handleAdminInput} placeholder="Buscar usuario..." class="p-2 border rounded-lg w-full" />
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
  </div>
  <button class="bg-cold-base text-white rounded-lg mx-6 p-4 px-6" type="submit" disabled={submitting}>
    {submitting ? 'Guardando...' : 'Guardar Local'}
  </button>
</form>
