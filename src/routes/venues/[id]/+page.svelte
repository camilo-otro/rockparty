<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';

  let venue: any = null;
  let parties: any[] = [];
  let loading = true;
  let error: string | null = null;
  let activeTab = 'upcoming';

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
      <h3 class="text-lg font-semibold mt-6 mb-2">Fiestas en este local</h3>
      <div class="flex gap-4 mb-4">
        <button class="px-4 py-2 rounded border-b-2" class:font-bold={activeTab === 'upcoming'} class:border-slate-700={activeTab === 'upcoming'} on:click={() => activeTab = 'upcoming'}>Próximas fiestas</button>
        <button class="px-4 py-2 rounded border-b-2" class:font-bold={activeTab === 'past'} class:border-slate-700={activeTab === 'past'} on:click={() => activeTab = 'past'}>Fiestas pasadas</button>
      </div>
      {#if activeTab === 'upcoming'}
        {#if getUpcomingParties().length === 0}
          <div>No hay próximas fiestas registradas.</div>
        {:else}
          <ul class="space-y-2">
            {#each getUpcomingParties() as party}
              <a href={`/parties/${party.id}`} class="block">
                <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
                  <div class="font-semibold">{party.date}</div>
                </li>
              </a>
            {/each}
          </ul>
        {/if}
      {:else if activeTab === 'past'}
        {#if getPastParties().length === 0}
          <div>No hay fiestas pasadas registradas.</div>
        {:else}
          <ul class="space-y-2">
            {#each getPastParties() as party}
              <a href={`/parties/${party.id}`} class="block">
                <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
                  <div class="font-semibold">{party.date}</div>
                </li>
              </a>
            {/each}
          </ul>
        {/if}
      {/if}
      <a href="/venues" class="text-blue-600 hover:underline">&larr; Volver a la lista</a>
    </div>
  {/if}
</div>
