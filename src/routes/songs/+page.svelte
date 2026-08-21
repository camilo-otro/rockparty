<script lang="ts">
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { ChevronLeft, Search, Plus } from 'lucide-svelte';

    let songs: any[] = [];
    let loading = true;
    let error: string | null = null;
    let query = '';
    let debounceTimer: ReturnType<typeof setTimeout>;

    // Rank exact/prefix matches above mid-string ones so the best hit is on top.
    function rank(list: any[], term: string) {
        const q = term.toLowerCase();
        const score = (s: any) => {
            const title = (s.title ?? '').toLowerCase();
            const artist = (s.artist ?? '').toLowerCase();
            if (title.startsWith(q)) return 0;
            if (artist.startsWith(q)) return 1;
            if (title.includes(q)) return 2;
            return 3;
        };
        return [...list].sort((a, b) => score(a) - score(b) || (a.title ?? '').localeCompare(b.title ?? ''));
    }

    async function loadSongs(raw: string) {
        loading = true;
        error = null;
        // Strip characters that would break the PostgREST or() filter string.
        const term = raw.trim().replace(/[%_,()]/g, '');
        let request = supabase.from('song').select('id, title, artist');
        if (term.length >= 2) {
            request = request.or(`title.ilike.%${term}%,artist.ilike.%${term}%`);
        }
        const { data, error: err } = await request.order('title', { ascending: true }).limit(50);
        if (err) {
            error = err.message;
            songs = [];
        } else {
            songs = term.length >= 2 ? rank(data ?? [], term) : (data ?? []);
        }
        loading = false;
    }

    function handleInput() {
        clearTimeout(debounceTimer);
        debounceTimer = setTimeout(() => loadSongs(query), 250);
    }

    onMount(() => loadSongs(''));
</script>

<div class="flex flex-col items-left">
    <div class="flex flex-row items-center">
        <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft/>VOLVER</a>
    </div>
    <section>
        <h2 class="text-3xl text-white m-4 mb-4">CANCIONES</h2>

        <div class="mx-4 mb-4 relative">
            <Search class="absolute left-3 top-1/2 -translate-y-1/2 text-cold-light" size={18} />
            <input
                type="search"
                bind:value={query}
                on:input={handleInput}
                placeholder="Buscar por título o artista..."
                class="w-full pl-10 pr-3 py-2 rounded-lg"
                autocomplete="off"
            />
        </div>

        <div class="m-4 rounded-lg overflow-clip flex flex-col">
            {#if loading}
                <div class="text-white p-4">Cargando...</div>
            {:else if error}
                <div class="text-red-500 p-4">Error: {error}</div>
            {:else if songs.length === 0}
                <div class="text-white p-4">
                    {query.trim().length >= 2 ? 'No se encontraron canciones.' : 'No hay ninguna canción registrada.'}
                </div>
            {:else}
                <ul class="p-0 space-y-[1px]">
                    {#each songs as song}
                        <a href={`/songs/${song.id}`} class="block">
                            <li class="bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-3">
                                <div class="text-lg text-white">{song.title}</div>
                                <div class="text-sm text-yellow">{song.artist}</div>
                            </li>
                        </a>
                    {/each}
                </ul>
                {#if query.trim().length < 2 && songs.length >= 50}
                    <div class="bg-base-900 text-cold-light text-sm text-center px-4 py-3">
                        Mostrando las primeras 50. Busca para encontrar una canción específica.
                    </div>
                {/if}
            {/if}
        </div>
    </section>
    <div class="flex justify-center p-4">
        <a class="text-center bg-cold-base text-white w-2/3 p-4 rounded-lg" href="/songs/create">Agregar una canción <Plus class="inline" /></a>
    </div>
</div>
