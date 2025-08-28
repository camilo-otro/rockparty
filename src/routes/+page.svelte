<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  let parties: any[] = [];
  let venues: any[] = [];
  let loading = true;
  let error: string | null = null;
  let topVenues: any[] = [];

  onMount(async () => {
    const { data: partyData, error: partyErr } = await supabase.from('party').select('id, title, date, venue').order('date', { ascending: true });
    const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name');
    if (partyErr || venueErr) {
      error = partyErr?.message ?? venueErr?.message ?? null;
    } else {
      parties = partyData ?? [];
      venues = venueData ?? [];
      // Get upcoming parties
      const now = new Date();
      const upcomingParties = parties.filter(p => new Date(p.date) >= now).sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
      // Find top venues by number of upcoming parties
      const venueCounts: Record<string | number, number> = {};
      for (const party of upcomingParties) {
        venueCounts[party.venue] = (venueCounts[party.venue] || 0) + 1;
      }
      topVenues = venues
        .map(v => ({ ...v, count: venueCounts[v.id] || 0 }))
        .sort((a, b) => b.count - a.count)
        .slice(0, 5);
      parties = upcomingParties.slice(0, 5);
    }
    loading = false;
  });

  function getVenueName(venueId: number) {
    const venue = venues.find(v => v.id === venueId);
    return venue ? venue.name : 'Sin nombre';
  }
</script>

<p class="bg-slate-200 p-2 px-4">Plan your next Rock Party!</p>
<div class="max-w-2xl mx-auto mt-8 flex flex-col gap-8">
  <section>
    <h2 class="text-xl font-bold m-4 mb-4">Próximas fiestas</h2>
    {#if loading}
      <div>Cargando...</div>
    {:else if error}
      <div class="text-red-500">Error: {error}</div>
    {:else if parties.length === 0}
      <div>No hay próximas fiestas registradas.</div>
    {:else}
      <ul class="space-y-2">
        {#each parties as party}
          <a href={`/parties/${party.id}`} class="block">
            <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
              <div class="font-semibold">{party.title}</div>
              <div class="text-sm text-slate-600">{party.date}</div>
              <div class="text-sm text-slate-600">{getVenueName(party.venue)}</div>
            </li>
          </a>
        {/each}
        <li class="p-4">
          <a href="/parties" class="btn btn-accent text-center bg-slate-700 text-slate-200 w-full px-4 p-2 rounded">Ver más</a>
        </li>
      </ul>
      
    {/if}
  </section>
  <section>
    <h2 class="text-xl font-bold m-4 mb-4">Locales con fiestas cercanas</h2>
    {#if loading}
      <div>Cargando...</div>
    {:else if error}
      <div class="text-red-500">Error: {error}</div>
    {:else if topVenues.length === 0}
      <div>No hay locales con fiestas próximas.</div>
    {:else}
      <ul class="space-y-2">
        {#each topVenues as venue}
          <a href={`/venues/${venue.id}`} class="block">
            <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
              <div class="font-semibold">{venue.name}</div>
              <div class="text-sm text-slate-600">{venue.count} fiestas próximas</div>
            </li>
          </a>
        {/each}
        <li class="p-4">
          <a href="/venues" class="btn btn-accent text-center bg-slate-700 text-slate-200 w-full px-4 p-2 rounded">Ver más</a>
        </li>
      </ul>
    {/if}
  </section>
</div>

