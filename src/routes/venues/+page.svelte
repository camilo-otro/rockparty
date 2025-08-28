<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ArrowLeft } from 'lucide-svelte';

    let venues: any[] = [];
    let parties: any[] = [];
    let loading = true;
    let error: string | null = null;

    onMount(async () => {
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('*');
        const { data: partyData, error: partyErr } = await supabase.from('party').select('id, date, venue');
        if (venueErr || partyErr) {
            error = venueErr?.message ?? partyErr?.message ?? null;
        } else {
            venues = venueData ?? [];
            parties = partyData ?? [];
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
        <a href="/" class="text-lg text-bold text-slate-700 flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> Volver</a>
    </div>
    <section>
        <h2 class="text-lg font-bold px-4 p-3 mb-2">Locales</h2>
        {#if loading}
            <div>Cargando...</div>
        {:else if error}
            <div class="text-red-500">Error: {error}</div>
        {:else if venues.length === 0}
            <div>No hay nngun local registrado.</div>
        {:else}
            <ul class="space-y-2">
                {#each venues as venue}
                    <a href={`/venues/${venue.id}`} class="block">
                        <li class="px-5 p-3 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition flex justify-between items-center">
                            <div>
                                <div class="font-semibold">{venue.name}</div>
                                <div class="text-sm text-slate-600">{venue.address}</div>
                            </div>
                            <div class="text-right text-slate-700">
                                {getUpcomingPartyCount(venue.id)} fiestas cercanas
                            </div>
                        </li>
                    </a>
                {/each}
            </ul>
        {/if}
    </section>
    <div class="flex justify-center p-4">
        <a class="btn btn-accent text-center bg-slate-700 text-slate-200 w-2/3 p-4 rounded" href="/venues/create">Agregar un local</a>
    </div>
</div>