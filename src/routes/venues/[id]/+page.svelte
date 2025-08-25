<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';

  let venue: any = null;
  let parties: any[] = [];
  let loading = true;
  let error: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('venue').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      venue = data;
      const { data: partyData } = await supabase.from('party').select('id, date').eq('venue', id);
      parties = partyData ?? [];
    }
    loading = false;
  });

  function getUpcomingParties() {
    const now = new Date();
    return parties.filter(p => new Date(p.date) >= now).sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
  }
  function getPastParties() {
    const now = new Date();
    return parties.filter(p => new Date(p.date) < now).sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  }
</script>

<div class="max-w-xl mx-auto mt-8">
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if venue}
    <div class="p-6 bg-slate-100 rounded shadow">
      <h2 class="text-2xl font-bold mb-2">{venue.name}</h2>
      <div class="mb-2 text-slate-700">Dirección: {venue.address}</div>
      <div class="mb-2 text-slate-700">Contacto: {venue.contact_name} ({venue.contact})</div>
      <h3 class="text-lg font-semibold mt-6 mb-2">Próximas fiestas</h3>
      <ul class="mb-4">
        {#each getUpcomingParties() as party}
          <li class="mb-2 p-2 bg-green-100 rounded">
            <a href={`/parties/${party.id}`} class="text-blue-700 underline">{party.date}</a>
          </li>
        {/each}
        {#if getUpcomingParties().length === 0}
          <li class="text-slate-500">No hay próximas fiestas.</li>
        {/if}
      </ul>
      <h3 class="text-lg font-semibold mt-6 mb-2">Fiestas pasadas</h3>
      <ul class="mb-4">
        {#each getPastParties() as party}
          <li class="mb-2 p-2 bg-gray-100 rounded">
            <a href={`/parties/${party.id}`} class="text-blue-700 underline">{party.date}</a>
          </li>
        {/each}
        {#if getPastParties().length === 0}
          <li class="text-slate-500">No hay fiestas pasadas.</li>
        {/if}
      </ul>
      <a href="/venues" class="text-blue-600 hover:underline">&larr; Volver a la lista</a>
    </div>
  {/if}
</div>
