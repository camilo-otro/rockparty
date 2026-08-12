<script lang="ts">
    import { ChevronLeft } from 'lucide-svelte';
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
    let loadingSongs = false;
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
    });

    onDestroy(() => {
      if (unsubscribeUser) unsubscribeUser();
    });

    $: if (songSearch && songSearch.length >= 3) {
      loadingSongs = true;
      supabase
        .from('song')
        .select('id, title, artist')
        .or(`title.ilike.%${songSearch}%,artist.ilike.%${songSearch}%`)
        .order('title', { ascending: true })
        .limit(20)
        .then(({ data, error }) => {
          if (error) {
            errorSongs = error.message;
            songs = [];
          } else {
            // Custom sort: title starts with, artist starts with, title contains, artist contains
            const sortedSongs = (data ?? []).sort((a, b) => {
              const searchLower = songSearch.toLowerCase();
              const aTitleStarts = (a.title ?? '').toLowerCase().startsWith(searchLower);
              const bTitleStarts = (b.title ?? '').toLowerCase().startsWith(searchLower);
              const aArtistStarts = (a.artist ?? '').toLowerCase().startsWith(searchLower);
              const bArtistStarts = (b.artist ?? '').toLowerCase().startsWith(searchLower);
              
              if (aTitleStarts && !bTitleStarts) return -1;
              if (!aTitleStarts && bTitleStarts) return 1;
              if (aArtistStarts && !bArtistStarts) return -1;
              if (!aArtistStarts && bArtistStarts) return 1;
              
              return (a.title ?? '').localeCompare(b.title ?? '');
            });
            songs = sortedSongs;
            errorSongs = null;
          }
          loadingSongs = false;
        });
    } else {
      songs = [];
      loadingSongs = false;
    }

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
                    party: partyId ? Number(partyId) : null,
                    song: Number(selectedSong),
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
<a href="/parties" class="text-bold text-cold-light flex flex-row px-4"><ChevronLeft />VOLVER</a>
<h2 class="text-yellow text-2xl px-5 py-2">AGREGA UNA CANCIÓN AL SETLIST</h2>
{#if !isAuthenticated}
  <div class="mt-8 p-6 text-white rounded-lg text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para agregar canciones al Setlist.
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
            <input id="ref_link" type="text" bind:value={refLink} class="p-2 border rounded-lg mb-4" in:fly={{ y: -30, duration: 400, delay: 100 }} />
            <label for="key" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Tonalidad</label>
            <input id="key" type="text" bind:value={key} class="p-2 border rounded-lg mb-4" in:fly={{ y: -30, duration: 400, delay: 150 }} />
        </div>
        <div class="flex justify-center" in:fly={{ y: -30, duration: 400, delay: 200 }}>
          <button class="bg-cold-base text-white text-sm rounded-full mx-auto p-2 px-6" type="submit" disabled={submitting || !!songError} in:fly={{ y: -30, duration: 400, delay: 200 }}>
              {submitting ? 'Creando...' : 'Agregar'}
          </button>
        </div>
    </form>
    <p class="mt-6 text-center text-slate-700">
      ¿No encuentras tu canción en la lista? <a href="/songs/create?from=performance&partyId={partyId}" class="text-blue-600 underline">Agregala aquí</a>.
    </p>
  {/if}
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Agregada al Setlist!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
  {/if}
{/if}
