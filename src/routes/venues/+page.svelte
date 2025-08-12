<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';

    let venues: any[] = [];
    let loading = true;
    let error: string | null = null;

    onMount(async () => {
        const { data, error: err } = await supabase.from('venue').select('*');
        if (err) {
            error = err.message;
        } else {
            venues = data ?? [];
        }
        loading = false;
    });
</script>
<div class="flex flex-col items-left gap-6">
    <section>
        <h2 class="text-lg font-bold mb-2">Locales</h2>
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
                        <li class="p-4 bg-slate-100 rounded shadow cursor-pointer hover:bg-slate-200 transition">
                            <div class="font-semibold">{venue.name}</div>
                            <div class="text-sm text-slate-600">{venue.address}</div>
                        </li>
                    </a>
                {/each}
            </ul>
        {/if}
    </section>
    <a class="btn btn-accent text-center bg-slate-700 text-slate-200 w-1/3 p-6 rounded" href="/venues/create">Agregar un local</a>
</div>