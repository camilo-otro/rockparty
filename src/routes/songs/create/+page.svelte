<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fade, fly } from 'svelte/transition';
    import { onMount } from 'svelte';
    import { fetchSongTitles, fetchArtistNames } from '$lib/musicbrainz';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import { page } from '$app/stores';
    import { supabase } from '$lib/supabaseClient';
    let submitting = false;
    let title = '';
    let artist = '';
    let key = '';
    let reflink = '';
    let titleSuggestions: string[] = [];
    let artistSuggestions: string[] = [];
    let titleTimeout: any = null;
    let artistTimeout: any = null;
    let userId: string | null = null;
    let fromPerformance = false;
    let partyId: string | null = null;
    let success = false;
    let error = '';

    onMount(() => {
        userId = get(user)?.id ?? null;
        const params = get(page).url.searchParams;
        fromPerformance = params.get('from') === 'performance';
        partyId = params.get('partyId');
    });

    async function handleSubmit() {
        if (!title || !artist) {
            error = 'Title and artist are required.';
            return;
        }
        
        submitting = true;
        error = '';
        
        try {
            const { data, error: dbError } = await supabase
                .from('song')
                .insert([{ title, artist, key: key || null, reflink: reflink || null, added_by: userId }])
                .select();
                
            if (dbError) {
                error = `Database error: ${dbError.message}`;
            } else {
                success = true;
                setTimeout(() => {
                    if (fromPerformance && partyId) {
                        window.location.href = `/performance/create?partyId=${partyId}`;
                    } else {
                        window.location.href = '/songs';
                    }
                }, 1000);
            }
        } catch (e) {
            error = 'Could not connect to the server.';
        }
        
        submitting = false;
    }

    function onTitleInput(e: Event) {
        title = (e.target as HTMLInputElement).value;
        if (titleTimeout) clearTimeout(titleTimeout);
        if (title.length >= 4) {
            titleTimeout = setTimeout(async () => {
                titleSuggestions = await fetchSongTitles(title) as string[];
            }, 1000);
        } else {
            titleSuggestions = [];
        }
    }

    function onArtistInput(e: Event) {
        artist = (e.target as HTMLInputElement).value;
        if (artistTimeout) clearTimeout(artistTimeout);
        if (artist.length >= 4) {
            artistTimeout = setTimeout(async () => {
                artistSuggestions = await fetchArtistNames(artist) as string[];
            }, 1000);
        } else {
            artistSuggestions = [];
        }
    }
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVA CANCIÓN</h2>
    <a href="/songs" class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
</div>
{#if !success && !error}
<form on:submit|preventDefault={handleSubmit}>
    <input type="hidden" name="added_by" value={userId} />
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="title" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Título</label>
        <input id="title" type="text" name="title" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} value={title} on:input={onTitleInput} autocomplete="off" />
        {#if titleSuggestions.length > 0}
          <ul class="bg-white border rounded shadow p-2 mt-1">
            {#each titleSuggestions as suggestion}
              <li class="cursor-pointer hover:bg-slate-200 p-1" on:click={() => { title = suggestion; titleSuggestions = []; }}>{suggestion}</li>
            {/each}
          </ul>
        {/if}
        <label for="artist" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Artista</label>
        <input id="artist" type="text" name="artist" required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }} value={artist} on:input={onArtistInput} autocomplete="off" />
        {#if artistSuggestions.length > 0}
          <ul class="bg-white border rounded shadow p-2 mt-1">
            {#each artistSuggestions as suggestion}
              <li class="cursor-pointer hover:bg-slate-200 p-1" on:click={() => { artist = suggestion; artistSuggestions = []; }}>{suggestion}</li>
            {/each}
          </ul>
        {/if}
        <label for="key" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 100 }}>Tonalidad</label>
        <input id="key" type="text" name="key" bind:value={key} class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 100 }} />
        <label for="reflink" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Referencia</label>
        <input id="reflink" type="text" name="reflink" bind:value={reflink} class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 150 }} />
    </div>
    <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 200 }}>
        {submitting ? 'Creando...' : 'Crear Canción'}
    </button>
</form>
{/if}
{#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Canción Creada!
    </div>
{/if}
{#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
{/if}
