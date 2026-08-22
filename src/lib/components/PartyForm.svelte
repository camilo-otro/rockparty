<script lang="ts">
  import { createEventDispatcher, onMount } from 'svelte';
  import { sanitizeString } from '$lib/sanitize';
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

  const dispatch = createEventDispatcher();

  // Local YYYY-MM-DD, used to block scheduling a toque in the past.
  const now = new Date();
  const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

  let title = initialTitle;
  let description = initialDescription;
  let date = initialDate;
  let selectedVenue = initialVenue;
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
    // Sanitize inputs
    const safeTitle = sanitizeString(title);
    const safeDescription = sanitizeString(description);
    const safeDate = sanitizeString(date);
    dispatch('submit', {
      title: safeTitle,
      description: safeDescription,
      date: safeDate,
      venue: selectedVenue,
      admins: admins.map(a => a.id)
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
      <select id="venue" bind:value={selectedVenue} required class="p-2 mb-4 border rounded-lg">
        <option value="" disabled selected>Selecciona un venue</option>
        {#each venues as venue}
          <option value={venue.id}>{venue.name}</option>
        {/each}
      </select>
    {/if}
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
  <div class="flex justify-center">
    <button class="bg-cold-base text-white text-sm rounded-full mx-4 p-2 px-6" type="submit" disabled={submitting}>
      {submitting ? 'Creando...' : 'Crear Toque'}
    </button>
  </div>
</form>
