<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { page } from '$app/state';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import SongSelect from '$lib/components/SongSelect.svelte';
    import { sanitizeString } from '$lib/sanitize';
    let submitting = false;
    let songs: any[] = [];
    let loadingSongs = true;
    let errorSongs: string | null = null;
    let partyId: string | null = null;
    let userId: string | null = null;
    let selectedSong = '';
    let songSearch = '';
    let songError = '';
    let refLink = '';
    let key = '';
    let success = false;
    let error = '';
    let isAuthenticated = false;
    let unsubscribeUser: () => void;

    onMount(async () => {
      unsubscribeUser = user.subscribe(u => {
        isAuthenticated = !!u?.id;
        userId = u?.id ?? null;
      });
        partyId = page.url.searchParams.get('partyId') ?? null;
        const { data, error } = await supabase.from('song').select('id, title, artist');
        if (error) {
            errorSongs = error.message;
        } else {
            songs = data ?? [];
        }
        loadingSongs = false;
    });

    onDestroy(() => {
      if (unsubscribeUser) unsubscribeUser();
    });

    async function handleSubmit() {
        if (!selectedSong || !partyId || !userId) {
            error = 'All required fields must be filled.';
            return;
        }
        
        // Sanitize inputs
        const safeRefLink = sanitizeString(refLink);
        const safeKey = sanitizeString(key);
        partyId = page.url.searchParams.get('partyId') ?? null;
        submitting = true;
        error = '';
        
        try {
            const { data, error: dbError } = await supabase
                .from('performance')
                .insert([{ 
                    party: partyId, 
                    song: selectedSong, 
                    suggested_by: userId, 
                    ref_link: safeRefLink || null, 
                    key: safeKey || null 
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

    function loginWithGoogle() {
      import('$lib/supabaseClient').then(({ supabase }) => {
        supabase.auth.signInWithOAuth({
          provider: 'google',
          options: { redirectTo: window.location.href }
        });
      });
    }
</script>
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVA PERFORMANCE</h2>
    <a href={partyId ? `/parties/${partyId}` : '/parties'} class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
</div>
{#if !isAuthenticated}
  <div class="mt-8 p-6 bg-yellow-100 text-yellow rounded-lg text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para crear una performance.
  </div>
{:else}
  {#if !success && !error}
    <form on:submit|preventDefault={handleSubmit}>
        <div class="flex flex-col w-3/4 p-5 mb-4">
            <label for="song" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Canción</label>
            <SongSelect 
              {songs} 
              bind:value={songSearch} 
              bind:selectedSongId={selectedSong} 
              bind:error={songError} 
            />
            {#if songError}
              <div class="text-red-600 text-sm mt-1">{songError}</div>
            {/if}
            <label for="ref_link" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 100 }}>Referencia</label>
            <input id="ref_link" type="text" bind:value={refLink} class="p-2 border rounded-lg" in:fly={{ y: -30, duration: 400, delay: 100 }} />
            <label for="key" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Tonalidad</label>
            <input id="key" type="text" bind:value={key} class="p-2 border rounded-lg" in:fly={{ y: -30, duration: 400, delay: 150 }} />
        </div>
        <button class="bg-slate-700 text-slate-200 rounded-lg mx-6 p-4 px-6" type="submit" disabled={submitting || !!songError} in:fly={{ y: -30, duration: 400, delay: 200 }}>
            {submitting ? 'Creando...' : 'Crear Performance'}
        </button>
    </form>
    <p class="mt-6 text-center text-slate-700">
      ¿No encuentras tu canción en la lista? <a href="/songs/create?from=performance&partyId={partyId}" class="text-blue-600 underline">Agregala aquí</a>.
    </p>
  {/if}
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Performance Creada!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
  {/if}
{/if}
