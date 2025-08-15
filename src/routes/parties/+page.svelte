<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ArrowLeft } from 'lucide-svelte';

    let parties: any[] = [];
    let venues: any[] = [];
    let loading = true;
    let error: string | null = null;

    onMount(async () => {
        const { data: partyData, error: partyErr } = await supabase.from('party').select('*');
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name');
        if (partyErr || venueErr) {
            error = partyErr?.message ?? venueErr?.message ?? null;
        } else {
            parties = partyData ?? [];
            venues = venueData ?? [];
        }
        loading = false;
    });

    function getVenueName(venueId: number) {
        const venue = venues.find(v => v.id === venueId);
        return venue ? venue.name : 'Sin nombre';
    }
</script>
<div class="flex flex-col items-left gap-6">
    <div class="mb-4">
        <a href="/" class="text-lg text-bold text-slate-700 flex items-center gap-2"><ArrowLeft/> Volver</a>
    </div>
    <section>
        <h2 class="text-lg font-bold mb-2">Rock Parties</h2>
        {#if loading}
            <div>Cargando...</div>
        {:else if error}
            <div class="text-red-500">Error: {error}</div>
        {:else if parties.length === 0}
            <div>No hay ninguna fiesta registrada.</div>
        {:else}
            <ul class="space-y-2">
                {#each parties as party}
                    <a href={`/parties/${party.id}`} class="block">
                        <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
                            <div class="font-semibold">{party.date}</div>
                            <div class="text-sm text-slate-600">{getVenueName(party.venue)}</div>
                        </li>
                    </a>
                {/each}
            </ul>
        {/if}
    </section>
    <a class="btn btn-accent text-center bg-slate-700 text-slate-200 w-1/3 p-6 rounded" href="/parties/create">Agregar una fiesta</a>
</div>
