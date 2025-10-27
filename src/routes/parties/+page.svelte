<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ChevronLeft, Plus } from 'lucide-svelte';
    import PartyListItem from '$lib/components/PartyListItem.svelte';

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
        <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft/>VOLVER</a>
    </div>
    <section>
        <div class="m-4 rounded-lg overflow-clip flex flex-col">
            <div class="flex gap-4 mb-4">
                <button class="px-4 py-2 border-b-2" class:border-yellow={activeTab === 'upcoming'} class:text-cold-light={activeTab === 'past'} class:border-none={activeTab === 'past'} on:click={() => activeTab = 'upcoming'}>PRÓXIMOS TOQUES</button>
                <button class="px-4 py-2 border-b-2" class:border-yellow={activeTab === 'past'} class:text-cold-light={activeTab === 'upcoming'} class:border-none={activeTab === 'upcoming'} on:click={() => activeTab = 'past'}>TOQUES PASADOS</button>
            </div>
            {#if loading}
                <div class="text-white p-4">Cargando...</div>
            {:else if error}
                <div class="text-red-500 p-4">Error: {error}</div>
            {:else if activeTab === 'upcoming'}
                <a class="btn btn-accent text-center bg-cold-base text-white w-2/3 rounded-t-lg w-full p-3" href="/parties/create">Organiza un nuevo toque <Plus class="inline" /></a>
                {#if getUpcomingParties().length === 0}
                    <div class="text-white p-4">No hay próximas fiestas registradas.</div>
                {:else}
                    <ul class="p-0 space-y-[1px]">
                        {#each getUpcomingParties() as party}
                            <PartyListItem party={party} venueName={getVenueName(party.venue)} />
                        {/each}
                    </ul>
                {/if}
            {:else if activeTab === 'past'}
                {#if getPastParties().length === 0}
                    <div class="text-white p-4">No hay fiestas pasadas registradas.</div>
                {:else}
                    <ul class="p-0 space-y-[1px]">
                        {#each getPastParties() as party}
                            <PartyListItem party={party} venueName={getVenueName(party.venue)} />
                        {/each}
                    </ul>
                {/if}
            {/if}
        </div>
    </section>
</div>
