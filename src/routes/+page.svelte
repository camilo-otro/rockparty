<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronsDown, Plus, MapPin } from 'lucide-svelte';
  let parties: any[] = [];
  let venues: any[] = [];
  let loading = true;
  let error: string | null = null;
  let topVenues: any[] = [];

  onMount(async () => {
    const { data: partyData, error: partyErr } = await supabase.from('party').select('id, title, date, venue').order('date', { ascending: true });
    const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name, address');
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

<div class="max-w-2xl mx-auto mt-8 flex flex-col gap-8">
  <section>
    <h2 class="text-3xl text-white m-4 mb-4">PRÓXIMOS TOQUES</h2>
    <div class="m-4 rounded-md overflow-clip flex flex-col">
      <a href="/parties/create" class="w-full bg-cold-base text-white text-sm block text-center p-2">Planea un nuevo toque <Plus class="inline-block" /></a>
      {#if loading}
        <div>Cargando...</div>
      {:else if error}
        <div class="text-red-500">Error: {error}</div>
      {:else if parties.length === 0}
        <div>No hay próximos toques registrados.</div>
      {:else}
        <ul class="p-0 space-y-[1px]">
          {#each parties as party}
            <a href={`/parties/${party.id}`} class="block">
              <li class="bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-2">
                <div class="text-2xl text-yellow">{party.title}</div>
                <div class="text-sm text-white">{party.date}</div>
                <div class="text-sm text-cold-light"><MapPin class="inline-block mr-1" size="15" stroke-width="4"/>{getVenueName(party.venue)}</div>
              </li>
            </a>
          {/each}
          <li class="bg-base-900 flex flex-row w-full">
            <a href="/parties" class="text-cold-light px-4 p-2 mx-auto">Ver más toques <ChevronsDown class="inline-block" /></a>
          </li>
        </ul>
        
      {/if}
    </div>
  </section>
  <section>
    <h2 class="text-3xl m-4 mb-4">LOCALES CERCANOS</h2>
    <div class="m-4 rounded-md overflow-clip flex flex-col">
      {#if loading}
        <div>Cargando...</div>
      {:else if error}
        <div class="text-red-500">Error: {error}</div>
      {:else if topVenues.length === 0}
        <div>No hay locales con fiestas próximas.</div>
      {:else}
        <ul class="p-0 space-y-[1px]">
          {#each topVenues as venue}
            <a href={`/venues/${venue.id}`} class="block">
              <li class="bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-2">
                <div class="text-xl text-yellow">{venue.name}</div>
                <div class="flex flex-row w-full justify-between">
                  <div class="text-sm">{venue.address}</div>
                  <div class="text-sm text-cold-light">{venue.count} toques</div>
                </div>
              </li>
            </a>
          {/each}
          <li class="bg-base-900 flex flex-row w-full">
            <a href="/venues" class="text-cold-light px-4 p-2 mx-auto">Ver más locales<ChevronsDown class="inline-block" /></a>
          </li>
        </ul>
      {/if}
    </div>
  </section>
</div>

