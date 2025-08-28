<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ArrowLeft } from 'lucide-svelte';

    let parties: any[] = [];
    let venues: any[] = [];
    let loading = true;
    let error: string | null = null;
    let activeTab = 'upcoming';

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

    function getUpcomingParties() {
        const now = new Date();
        return parties.filter(p => new Date(p.date) >= now).sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
    }
    function getPastParties() {
        const now = new Date();
        return parties.filter(p => new Date(p.date) < now).sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
    }
</script>
<div class="flex flex-col items-left">
    <div class="flex flex-row items-center">
        <a href="/" class="text-lg text-bold text-slate-700 flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> Volver</a>
    </div>
    <section>
        <h2 class="text-lg font-bold mb-2 px-4 p-3">Rock Parties</h2>
        <div class="flex gap-4 mb-4">
            <button class="px-4 py-2 rounded border-b-2" class:font-bold={activeTab === 'upcoming'} class:border-slate-700={activeTab === 'upcoming'} on:click={() => activeTab = 'upcoming'}>Próximas fiestas</button>
            <button class="px-4 py-2 rounded border-b-2" class:font-bold={activeTab === 'past'} class:border-slate-700={activeTab === 'past'} on:click={() => activeTab = 'past'}>Fiestas pasadas</button>
        </div>
        {#if loading}
            <div>Cargando...</div>
        {:else if error}
            <div class="text-red-500">Error: {error}</div>
        {:else if activeTab === 'upcoming'}
            {#if getUpcomingParties().length === 0}
                <div>No hay próximas fiestas registradas.</div>
            {:else}
                <ul class="space-y-2">
                    {#each getUpcomingParties() as party}
                        <a href={`/parties/${party.id}`} class="block">
                            <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
                                <div class="font-semibold">{party.title}</div>
                                <div class="text-sm text-slate-600">{party.date}</div>
                                <div class="text-sm text-slate-600">{getVenueName(party.venue)}</div>
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
                                <div class="font-semibold">{party.title}</div>
                                <div class="text-sm text-slate-600">{party.description}</div>
                                <div class="text-sm text-slate-600">{party.date}</div>
                                <div class="text-sm text-slate-600">{getVenueName(party.venue)}</div>
                            </li>
                        </a>
                    {/each}
                </ul>
            {/if}
        {/if}
    </section>
    <div class="flex justify-center p-4">
      <a class="btn btn-accent text-center bg-slate-700 text-slate-200 w-2/3 p-4 rounded" href="/parties/create">Organizar Fiesta</a>
    </div>
</div>
