<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ArrowLeft } from 'lucide-svelte';

    let songs: any[] = [];
    let loading = true;
    let error: string | null = null;

    onMount(async () => {
        const { data, error: err } = await supabase.from('song').select('*');
        if (err) {
            error = err.message;
        } else {
            songs = data ?? [];
        }
        loading = false;
    });
</script>
<div class="flex flex-col items-left gap-6">
    <div class="mb-4">
        <a href="/" class="text-bold text-cold-light flex items-center gap-2"><ArrowLeft/>VOLVER</a>
    </div>
    <section>
        <h2 class="text-lg font-bold mb-2 px-4 p-3">Canciones</h2>
        {#if loading}
            <div>Cargando...</div>
        {:else if error}
            <div class="text-red-500">Error: {error}</div>
        {:else if songs.length === 0}
            <div>No hay ninguna canción registrada.</div>
        {:else}
            <ul class="space-y-2">
                {#each songs as song}
                    <a href={`/songs/${song.id}`} class="block">
                        <li class="p-4 bg-slate-100 rounded-lg shadow cursor-pointer hover:bg-slate-200 transition">
                            <div class="font-semibold">{song.title}</div>
                            <div class="text-sm text-slate-600">Artista: {song.artist}</div>
                        </li>
                    </a>
                {/each}
            </ul>
        {/if}
    </section>
    <div class="flex justify-center">
        <a class="btn btn-accent text-center bg-slate-700 text-slate-200 w-2/3 p-6 rounded-lg" href="/songs/create">Agregar una canción</a>
    </div>
</div>
