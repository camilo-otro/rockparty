<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ChevronLeft } from 'lucide-svelte';
    import VenueListItem from '$lib/components/VenueListItem.svelte';

    let venues: any[] = [];
    let parties: any[] = [];
    let loading = true;
    let error: string | null = null;

    onMount(async () => {
        const { data: partyData, error: partyErr } = await supabase.from('party').select('id, venue');
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name, address');
        if (partyErr || venueErr) {
            error = partyErr?.message ?? venueErr?.message ?? null;
        } else {
            // Calculate party count for each venue
            const venueCounts: Record<string | number, number> = {};
            for (const party of partyData ?? []) {
                venueCounts[party.venue] = (venueCounts[party.venue] || 0) + 1;
            }
            venues = (venueData ?? []).map(v => ({ ...v, count: venueCounts[v.id] || 0 }));
        }
        loading = false;
    });

    function getUpcomingPartyCount(venueId: number) {
        const now = new Date();
        const thirtyDays = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
        return parties.filter(p => p.venue === venueId && new Date(p.date) >= now && new Date(p.date) <= thirtyDays).length;
    }
</script>
<div class="flex flex-col items-left">
    <div class="flex flex-row items-center">
        <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft/>VOLVER</a>
    </div>
    <section>
        <h2 class="text-3xl text-white m-4 mb-4">LOCALES</h2>
        <div class="m-4 rounded-lg overflow-clip flex flex-col">
            {#if loading}
                <div class="text-white p-4">Cargando...</div>
            {:else if error}
                <div class="text-red-500 p-4">Error: {error}</div>
            {:else if venues.length === 0}
                <div class="text-white p-4">No hay locales registrados.</div>
            {:else}
                <ul class="p-0 space-y-[1px]">
                  {#each venues as venue}
                    <VenueListItem venue={venue} />
                  {/each}
                </ul>
            {/if}
        </div>
    </section>
    <div class="flex justify-center p-4">
        <a class="btn btn-accent text-center bg-slate-700 text-slate-200 w-2/3 p-4 rounded-lg" href="/venues/create">Agregar un local</a>
    </div>
</div>