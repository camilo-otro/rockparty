<script lang="ts">
  import { createEventDispatcher, onMount } from 'svelte';
  import { normalizeText } from '$lib/sanitize';
  import { supabase } from '$lib/supabaseClient';
  export let venues: any[] = [];
  export let loadingVenues: boolean = false;
  export let errorVenues: string | null = null;
  export let initialTitle: string = '';
  export let initialDescription: string = '';
  export let initialDate: string = '';
  export let initialVenue: string = '';
  export let submitting: boolean = false;
  export let success: boolean = false;
  export let error: string = '';
  export let userId: string | null = null;
  export let isAuthenticated: boolean = false;
  export let initialAdmins: string[] = [];
  export let initialPerformerApproval: string = 'auto';
  export let submitLabel: string = 'Crear Toque';
  export let submittingLabel: string = 'Creando...';
  // When editing, the toque being edited shouldn't flag itself as a conflict.
  export let excludePartyId: number | null = null;

  const dispatch = createEventDispatcher();

  // Scheduled toques used to warn about venue/date conflicts (#54). Only counts
  // toques that occupy the venue (confirmed/pending/live); RLS limits these to
  // public ones plus the viewer's own / their venues'.
  let scheduled: { id: number; venue: number | null; date: string | null }[] = [];
  $: busyVenues = date
    ? new Set(scheduled.filter((s) => s.date === date && s.id !== excludePartyId && s.venue != null).map((s) => s.venue as number))
    : new Set<number>();
  $: selectedVenueBusy = !!date && selectedVenue !== '' && busyVenues.has(Number(selectedVenue));

  // How musicians get onto a song (#29).
  const approvalModes = [
    { value: 'auto', label: 'Abierto — cualquiera puede sumarse' },
    { value: 'organizer', label: 'El organizador aprueba cada inscripción' },
    { value: 'proponent', label: 'Quien sugiere la canción aprueba a sus músicos' },
    { value: 'invite_only', label: 'Solo por invitación — sin inscripciones abiertas' }
  ];

  // Local YYYY-MM-DD, used to block scheduling a toque in the past.
  const now = new Date();
  const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

  let title = initialTitle;
  let description = initialDescription;
  let date = initialDate;
  let selectedVenue = initialVenue;
  let performerApproval = initialPerformerApproval;
  let admins: any[] = [];
  let userOptions: any[] = [];
  let adminInput = '';
  let filteredOptions: any[] = [];

  onMount(async () => {
    // Fetch all users for autocomplete
    const { data: users } = await supabase.from('profile').select('id, nickname');
    userOptions = users ?? [];
    // Pre-fill admins if editing
    if (initialAdmins && initialAdmins.length > 0) {
      admins = userOptions.filter(u => initialAdmins.includes(u.id));
    }
    // Upcoming toques that occupy a venue, for the conflict warning (#54).
    const { data: sched } = await supabase
      .from('party')
      .select('id, venue, date')
      .in('status', ['confirmed', 'pending_venue', 'live'])
      .gte('date', todayStr);
    scheduled = sched ?? [];
  });

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
    if (!date || !selectedVenue || !title) {
      dispatch('error', 'All fields are required.');
      return;
    }
    if (date < todayStr) {
      dispatch('error', 'La fecha no puede ser en el pasado.');
      return;
    }
    dispatch('submit', {
      title: normalizeText(title, 120),
      description: normalizeText(description, 2000),
      date,
      venue: selectedVenue,
      admins: admins.map(a => a.id),
      performerApproval
    });
  }
</script>

<form on:submit|preventDefault={handleSubmit}>
  <div class="flex flex-col w-full p-4 mb-4">
    <label for="title" class="mb-1">Título</label>
    <input id="title" type="text" bind:value={title} required class="p-2 mb-4 border rounded-lg" />
    <label for="description" class="mb-1">Descripción</label>
    <textarea id="description" bind:value={description} class="p-2 mb-4 border rounded-lg" rows="3"></textarea>
    <label for="date" class="mb-1">Fecha</label>
    <input id="date" type="date" bind:value={date} min={todayStr} required class="p-2 mb-4 border rounded-lg" />
    <label for="venue" class="mb-1">Venue</label>
    {#if loadingVenues}
      <div class="text-slate-600">Cargando venues...</div>
    {:else if errorVenues}
      <div class="text-red-600">Error: {errorVenues}</div>
    {:else}
      <select id="venue" bind:value={selectedVenue} required class="p-2 mb-1 border rounded-lg">
        <option value="" disabled selected>Selecciona un venue</option>
        {#each venues as venue}
          <option value={venue.id}>{venue.name}{busyVenues.has(venue.id) ? ' · ocupado ese día' : ''}</option>
        {/each}
      </select>
      {#if selectedVenueBusy}
        <span class="text-sm text-yellow mb-4">Este local ya tiene un toque ese día. Puedes continuar; el local podrá confirmarlo o rechazarlo.</span>
      {:else}
        <div class="mb-4"></div>
      {/if}
    {/if}
    <label for="performer_approval" class="mb-1 mt-4">¿Cómo se suman los músicos?</label>
    <select id="performer_approval" bind:value={performerApproval} class="p-2 mb-1 border rounded-lg">
      {#each approvalModes as m}
        <option value={m.value}>{m.label}</option>
      {/each}
    </select>
    <span class="text-sm text-cold-light mb-4">Los administradores del toque siempre pueden aprobar y sumar músicos.</span>

    <label for="admins" class="mb-1 mt-4">Administradores del toque</label>
    <div class="mb-2">
      <input id="admins" type="text" bind:value={adminInput} on:input={handleAdminInput} placeholder="Buscar usuario..." class="p-2 mb-4 border rounded-lg w-full" />
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
  <div class="flex justify-center mb-8">
    <button class="bg-cold-base text-white text-sm rounded-full mx-4 p-2 px-6" type="submit" disabled={submitting}>
      {submitting ? submittingLabel : submitLabel}
    </button>
  </div>
</form>
