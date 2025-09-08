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
        <h2 class="text-3xl text-white m-4 mb-4">ROCK PARTIES</h2>
        <div class="m-4 rounded-md overflow-clip flex flex-col">
            <div class="flex gap-4 mb-4">
                <button class="px-4 py-2 rounded border-b-2 text-white" class:font-bold={activeTab === 'upcoming'} class:border-yellow={activeTab === 'upcoming'} on:click={() => activeTab = 'upcoming'}>Próximas fiestas</button>
                <button class="px-4 py-2 rounded border-b-2 text-white" class:font-bold={activeTab === 'past'} class:border-yellow={activeTab === 'past'} on:click={() => activeTab = 'past'}>Fiestas pasadas</button>
            </div>
            {#if loading}
                <div class="text-white p-4">Cargando...</div>
            {:else if error}
                <div class="text-red-500 p-4">Error: {error}</div>
            {:else if activeTab === 'upcoming'}
                {#if getUpcomingParties().length === 0}
                    <div class="text-white p-4">No hay próximas fiestas registradas.</div>
                {:else}
                    <ul class="p-0 space-y-[1px]">
                        {#each getUpcomingParties() as party}
                            <a href={`/parties/${party.id}`} class="block">
                                <li class="bg-base-900 cursor-pointer hover:bg-slate-200 transition px-4 py-2">
                                    <div class="text-2xl text-yellow">{party.title}</div>
                                    <div class="text-sm text-white">{party.date}</div>
                                    <div class="text-sm text-cold-light">{getVenueName(party.venue)}</div>
                                </li>
                            </a>
                        {/each}
                    </ul>
                {/if}
            {:else if activeTab === 'past'}
                {#if getPastParties().length === 0}
                    <div class="text-white p-4">No hay fiestas pasadas registradas.</div>
                {:else}
                    <ul class="p-0 space-y-[1px]">
                        {#each getPastParties() as party}
                            <a href={`/parties/${party.id}`} class="block">
                                <li class="bg-base-900 cursor-pointer hover:bg-slate-200 transition px-4 py-2">
                                    <div class="text-2xl text-yellow">{party.title}</div>
                                    <div class="text-sm text-white">{party.description}</div>
                                    <div class="text-sm text-white">{party.date}</div>
                                    <div class="text-sm text-cold-light">{getVenueName(party.venue)}</div>
                                </li>
                            </a>
                        {/each}
                    </ul>
                {/if}
            {/if}
        </div>
    </section>
    <div class="flex justify-center p-4">
      <a class="btn btn-accent text-center bg-cold-base text-white w-2/3 p-4 rounded" href="/parties/create">Organizar Fiesta</a>
    </div>
</div>
