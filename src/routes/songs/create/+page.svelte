<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fade, fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { fetchSongTitles, fetchArtistNames } from '$lib/musicbrainz';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import { page } from '$app/stores';
    import { supabase } from '$lib/supabaseClient';
    import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
    import AutocompleteInput from '$lib/components/AutocompleteInput.svelte';
    import { sanitizeString } from '$lib/sanitize';
    let submitting = false;
    let title = '';
    let artist = '';
    let reflink = '';
    let titleSuggestions: string[] = [];
    let artistSuggestions: string[] = [];
    let titleTimeout: any = null;
    let artistTimeout: any = null;
    let userId: string | null = null;
    let fromPerformance = false;
    let partyId: string | null = null;
    let isAuthenticated = false;
    let unsubscribeUser: () => void;

    onMount(async () => {
      unsubscribeUser = user.subscribe(u => {
        isAuthenticated = !!u?.id;
        userId = u?.id ?? null;
      });
        const params = get(page).url.searchParams;
        fromPerformance = params.get('from') === 'performance';
        partyId = params.get('partyId');
    });

    onDestroy(() => {
      if (unsubscribeUser) unsubscribeUser();
    });

    async function handleSubmit() {
        if (!title || !artist) {
            toastError('Todos los campos son obligatorios.');
            return;
        }
        // Sanitize inputs
        const safeTitle = sanitizeString(title);
        const safeArtist = sanitizeString(artist);
        submitting = true;

        try {
            const { supabase } = await import('$lib/supabaseClient');
            const { data, error: dbError } = await supabase
                .from('song')
                .insert([{ title: safeTitle, artist: safeArtist, added_by: userId, ref_link: reflink }])
                .select();

            if (dbError) {
                reportError(dbError);
            } else {
                toastSuccess('¡Nueva canción creada!');
                setTimeout(() => {
                    if (fromPerformance && partyId) {
                        window.location.href = `/performance/create?partyId=${partyId}`;
                    } else {
                        window.location.href = '/songs';
                    }
                }, 500);
            }
        } catch (e) {
            toastError('No se pudo conectar con el servidor.');
        }

        submitting = false;
    }

    function onTitleInput(value: string) {
        title = value;
        if (titleTimeout) clearTimeout(titleTimeout);
        if (title.length >= 4) {
            titleTimeout = setTimeout(async () => {
                titleSuggestions = await fetchSongTitles(title) as string[];
            }, 1000);
        } else {
            titleSuggestions = [];
        }
    }

    function onArtistInput(value: string) {
        artist = value;
        if (artistTimeout) clearTimeout(artistTimeout);
        if (artist.length >= 4) {
            artistTimeout = setTimeout(async () => {
                artistSuggestions = await fetchArtistNames(artist) as string[];
            }, 1000);
        } else {
            artistSuggestions = [];
        }
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
<div class="bg-cold-base p-4 flex-row">
    <h2 class="text-white text-2xl">AGREGAR NUEVA CANCIÓN</h2>
    <a href="/songs" class="text-lg text-bold text-cold-light"><ArrowLeft/></a>
</div>
{#if !isAuthenticated}
  <div class="mt-8 p-6 bg-yellow-100 text-yellow-800 rounded-lg text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para crear una canción.
  </div>
{:else}
    <form on:submit|preventDefault={handleSubmit}>
        <input type="hidden" name="added_by" value={userId} />
        <div class="flex flex-col w-3/4 p-5 mb-4">
            <label for="title" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Título</label>
            <AutocompleteInput 
              id="title" 
              bind:value={title} 
              suggestions={titleSuggestions}
              onInput={onTitleInput}
              placeholder="Título de la canción"
              required
            />
            <label for="artist" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Artista</label>
            <AutocompleteInput 
              id="artist" 
              bind:value={artist} 
              suggestions={artistSuggestions}
              onInput={onArtistInput}
              placeholder="Nombre del artista"
              required
            />
            <label for="reflink" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Referencia</label>
            <input id="reflink" type="text" name="reflink" bind:value={reflink} class="p-2 border rounded-lg" in:fly={{ y: -30, duration: 400, delay: 150 }} />
        </div>
        <button class="bg-cold-base text-white rounded-lg mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 200 }}>
            {submitting ? 'Creando...' : 'Crear Canción'}
        </button>
    </form>
{/if}
