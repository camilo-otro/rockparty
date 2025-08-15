<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft } from 'lucide-svelte';

  let party: any = null;
  let venue: any = null;
  let performances: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('party').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      party = data;
      if (party?.venue) {
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('name').eq('id', party.venue).single();
        if (!venueErr) {
          venue = venueData;
        }
      }
      // Fetch performances for this party
      const { data: perfData, error: perfErr } = await supabase.from('performance').select('id, song, suggested_by, ref_link, key').eq('party', id);
      if (perfErr) {
        errorPerformances = perfErr.message;
      } else {
        performances = perfData ?? [];
      }
      loadingPerformances = false;
    }
    loading = false;
  });
</script>

<div class="max-w-xl mx-auto mt-8">
  <div class="mb-4">
    <a href="/parties" class="text-lg text-bold text-slate-700 flex items-center gap-2"><ArrowLeft/> Volver</a>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if party}
    <div class="p-6 bg-slate-100 rounded shadow">
      <h2 class="text-2xl font-bold mb-2">{party.date}</h2>
      <div class="mb-2 text-slate-700">Venue: {venue ? venue.name : 'Cargando...'}</div>
      <h3 class="text-lg font-semibold mt-4 mb-2">Performances</h3>
      {#if loadingPerformances}
        <div>Cargando performances...</div>
      {:else if errorPerformances}
        <div class="text-red-500">Error: {errorPerformances}</div>
      {:else if performances.length === 0}
        <div>No hay performances para esta fiesta.</div>
      {:else}
        <ul class="mb-4">
          {#each performances as perf}
            <li class="mb-2 p-2 bg-slate-200 rounded">
              Canción ID: {perf.song} | Sugerido por: {perf.suggested_by} | Tonalidad: {perf.key}
              {#if perf.ref_link}
                | <a href={perf.ref_link} target="_blank" class="text-blue-600 underline">Referencia</a>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
      <a href={`/performance/create?partyId=${party.id}`} class="bg-slate-700 text-slate-200 rounded p-2 px-4 inline-block mt-2">Sugerir performance</a>
      <a href="/parties" class="text-blue-600 hover:underline block mt-4">&larr; Volver a la lista</a>
    </div>
  {/if}
</div>
