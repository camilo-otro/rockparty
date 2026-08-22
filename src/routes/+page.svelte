<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, ChevronsDown, Plus, MapPin } from 'lucide-svelte';
  import PartyListItem from '$lib/components/PartyListItem.svelte';
  import VenueListItem from '$lib/components/VenueListItem.svelte';

  let parties: any[] = [];
  let venues: any[] = [];
  let loading = true;
  let error: string | null = null;
  let topVenues: any[] = [];

  onMount(async () => {
    const { data: partyData, error: partyErr } = await supabase.from('party').select('id, title, date, venue').in('status', ['confirmed', 'live']).order('date', { ascending: true });
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

<div class="mt-8 flex flex-col gap-8">
  <section class="mx-4">
    <div class="bg-base-900 rounded-lg p-6 text-center">
      <p class="text-white text-lg leading-snug">
        Conéctate con <span class="font-bold">músicos</span>, encuentra <span class="font-bold">locales</span> y lleva tu música al <span class="font-bold">siguiente nivel</span>.
      </p>
      <a href="/como-funciona" class="text-cold-light inline-block mt-3 hover:underline">Aprende cómo funciona</a>
    </div>
  </section>
  <section>
    <h2 class="text-3xl text-white m-4 mb-4">PRÓXIMOS TOQUES</h2>
    <div class="m-4 rounded-lg overflow-clip flex flex-col">
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
            <PartyListItem party={party} venueName={getVenueName(party.venue)} />
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
    <div class="m-4 rounded-lg overflow-clip flex flex-col">
      {#if loading}
        <div>Cargando...</div>
      {:else if error}
        <div class="text-red-500">Error: {error}</div>
      {:else if topVenues.length === 0}
        <div>No hay locales con fiestas próximas.</div>
      {:else}
        <ul class="p-0 space-y-[1px]">
          {#each topVenues as venue}
            <VenueListItem venue={venue} />
          {/each}
          <li class="bg-base-900 flex flex-row w-full">
            <a href="/venues" class="text-cold-light px-4 p-2 mx-auto">Ver más locales<ChevronsDown class="inline-block" /></a>
          </li>
        </ul>
      {/if}
    </div>
  </section>
</div>

