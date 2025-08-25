<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { page } from '$app/stores';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    let submitting = false;
    let songs: any[] = [];
    let loadingSongs = true;
    let errorSongs: string | null = null;
    let partyId: string | null = null;
    let userId: string | null = null;
    let selectedSong = '';
    let refLink = '';
    let key = '';
    let success = false;
    let error = '';

    onMount(async () => {
        partyId = get(page).url.searchParams.get('partyId') ?? null;
        userId = get(user)?.id ?? null;
        const { data, error } = await supabase.from('song').select('id, title');
        if (error) {
            errorSongs = error.message;
        } else {
            songs = data ?? [];
        }
        loadingSongs = false;
    });

    async function handleSubmit() {
        if (!selectedSong || !partyId || !userId) {
            error = 'All required fields must be filled.';
            return;
        }
        
        submitting = true;
        error = '';
        
        try {
            const { data, error: dbError } = await supabase
                .from('performance')
                .insert([{ 
                    party: partyId, 
                    song: selectedSong, 
                    suggested_by: userId, 
                    ref_link: refLink || null, 
                    key: key || null 
                }])
                .select();
                
            if (dbError) {
                error = `Database error: ${dbError.message}`;
            } else {
                success = true;
                setTimeout(() => {
                    window.location.href = `/parties/${partyId}`;
                }, 1000);
            }
        } catch (e) {
            error = 'Could not connect to the server.';
        }
        
        submitting = false;
    }
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVA PERFORMANCE</h2>
    <a href="/parties" class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
</div>
{#if !success && !error}
<form on:submit|preventDefault={handleSubmit}>
    <div class="flex flex-col w-3/4 p-5 mb-4">
        <label for="song" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Canción</label>
        {#if loadingSongs}
          <div class="text-slate-600">Cargando canciones...</div>
        {:else if errorSongs}
          <div class="text-red-600">Error: {errorSongs}</div>
        {:else}
          <select id="song" bind:value={selectedSong} required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }}>
            <option value="" disabled selected>Selecciona una canción</option>
            {#each songs as song}
              <option value={song.id}>{song.title}</option>
            {/each}
          </select>
        {/if}
        <label for="ref_link" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 100 }}>Referencia</label>
        <input id="ref_link" type="text" bind:value={refLink} class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 100 }} />
        <label for="key" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Tonalidad</label>
        <input id="key" type="text" bind:value={key} class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 150 }} />
    </div>
    <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 200 }}>
        {submitting ? 'Creando...' : 'Crear Performance'}
    </button>
</form>
<p class="mt-6 text-center text-slate-700">
  ¿No encuentras la canción en la lista? <a href="/songs/create?from=performance&partyId={partyId}" class="text-blue-600 underline">Agrega una nueva canción aquí</a>.
</p>
{/if}
{#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Performance Creada!
    </div>
{/if}
{#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
{/if}
