<script lang="ts">
    import { ArrowLeft, Search, ExternalLink } from 'lucide-svelte';
    import { goto } from '$app/navigation';
    import { onMount, onDestroy } from 'svelte';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import { page } from '$app/stores';
    import { supabase } from '$lib/supabaseClient';
    import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
    import { normalizeText } from '$lib/sanitize';
    import { tidySpotifyResults } from '$lib/spotify';

    let userId: string | null = null;
    let isAuthenticated = false;
    let unsubscribeUser: () => void;
    let fromPerformance = false;
    let partyId: string | null = null;

    // In-app Spotify search (#83)
    let query = '';
    let searching = false;
    let searchError = '';
    let results: { title: string; artist: string; art_url: string | null; spotify_url: string }[] = [];
    let submitting = false;
    let searchSeq = 0;
    let searchTimer: any = null;

    // Manual fallback (songs not on Spotify)
    let manualOpen = false;
    let mTitle = '';
    let mArtist = '';

    onMount(() => {
      unsubscribeUser = user.subscribe((u) => { isAuthenticated = !!u?.id; userId = u?.id ?? null; });
      const params = get(page).url.searchParams;
      fromPerformance = params.get('from') === 'performance';
      partyId = params.get('partyId');
    });
    onDestroy(() => { if (unsubscribeUser) unsubscribeUser(); clearTimeout(searchTimer); });

    function continueFlow() {
      setTimeout(() => {
        if (fromPerformance && partyId) goto(`/performance/create?partyId=${partyId}`);
        else goto('/songs');
      }, 500);
    }

    // Debounced Spotify search with a latest-wins guard.
    $: scheduleSearch(query);
    function scheduleSearch(q: string) {
      clearTimeout(searchTimer);
      const term = (q ?? '').trim();
      searchError = '';
      if (term.length < 2) { results = []; return; }
      searchTimer = setTimeout(() => runSearch(term), 300);
    }
    async function runSearch(term: string) {
      const seq = ++searchSeq;
      searching = true;
      try {
        const { data, error } = await supabase.functions.invoke('spotify-track', { body: { q: term } });
        if (seq !== searchSeq) return; // superseded
        if (error || (data as any)?.error) { searchError = 'No se pudo buscar en Spotify. Intenta de nuevo.'; results = []; return; }
        // Drop remix/live versions and strip remaster tags from the kept titles.
        results = tidySpotifyResults((data as any).results ?? []);
      } catch {
        if (seq === searchSeq) { searchError = 'No se pudo conectar con el servidor.'; results = []; }
      } finally {
        if (seq === searchSeq) searching = false;
      }
    }

    // Reuse an existing song (by Spotify link, else title+artist) or insert a new
    // one, then continue.
    async function insertOrReuse(row: { title: string; artist: string; ref_link: string | null }) {
      if (submitting) return;
      submitting = true;
      try {
        if (row.ref_link) {
          const { data: existing } = await supabase.from('song').select('id').eq('ref_link', row.ref_link).maybeSingle();
          if (existing) { toastSuccess('Esa canción ya estaba en la app.'); continueFlow(); return; }
        }
        const { error } = await supabase.from('song').insert([{ title: row.title, artist: row.artist, ref_link: row.ref_link, added_by: userId }]);
        if (error) {
          if ((error as any).code === '23505') { toastSuccess('Esa canción ya estaba en la app.'); continueFlow(); return; }
          reportError(error); return;
        }
        toastSuccess('¡Canción agregada!');
        continueFlow();
      } catch {
        toastError('No se pudo conectar con el servidor.');
      } finally {
        submitting = false;
      }
    }

    function addResult(r: { title: string; artist: string; spotify_url: string }) {
      insertOrReuse({ title: normalizeText(r.title, 200), artist: normalizeText(r.artist, 200), ref_link: r.spotify_url });
    }

    function addManual() {
      const title = normalizeText(mTitle, 200);
      const artist = normalizeText(mArtist, 200);
      if (!title || !artist) { toastError('Título y artista son obligatorios.'); return; }
      insertOrReuse({ title, artist, ref_link: null });
    }

    function loginWithGoogle() {
      supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.href } });
    }
</script>

<div class="bg-cold-base p-4 flex items-center gap-2">
  <a href={fromPerformance && partyId ? `/performance/create?partyId=${partyId}` : '/songs'} class="text-cold-light hover:text-white"><ArrowLeft /></a>
  <h2 class="text-white text-2xl">AGREGAR UNA CANCIÓN</h2>
</div>

{#if !isAuthenticated}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para crear una canción.
  </div>
{:else}
  <div class="flex flex-col gap-4 p-4">
    <div class="flex flex-col gap-1">
      <label for="song-search" class="text-cold-light text-sm">Busca la canción en Spotify</label>
      <div class="relative">
        <Search size={16} class="text-cold-light absolute left-3 top-1/2 -translate-y-1/2" />
        <input id="song-search" type="text" bind:value={query} autocomplete="off"
               placeholder="Título y/o artista…" class="w-full p-2 pl-9 border rounded-lg" />
      </div>
      {#if searchError}<div class="text-red-500 text-sm">{searchError}</div>{/if}
    </div>

    {#if results.length}
      <div class="flex flex-col gap-2">
        <span class="text-xs text-cold-light/70 inline-flex items-center gap-1">
          <img src="/images/spotify-logo.svg" alt="Spotify" class="h-3" on:error={(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')} /> Resultados de Spotify
        </span>
        <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
          {#each results as r}
            <li class="bg-base-900 flex items-center gap-1 pr-2">
              <button type="button" on:click={() => addResult(r)} disabled={submitting}
                      class="flex-1 min-w-0 hover:bg-base-950 transition px-3 py-2 flex items-center gap-3 text-left disabled:opacity-60">
                {#if r.art_url}<img src={r.art_url} alt="" class="w-11 h-11 rounded object-cover shrink-0" />{/if}
                <div class="min-w-0 flex-1">
                  <div class="text-yellow truncate">{r.title}</div>
                  <div class="text-sm text-cold-light truncate">{r.artist}</div>
                </div>
              </button>
              <a href={r.spotify_url} target="_blank" rel="noopener" class="text-cold-light/60 hover:text-cold-light shrink-0 p-1" aria-label="Abrir en Spotify"><ExternalLink size={15} /></a>
            </li>
          {/each}
        </ul>
      </div>
    {:else if searching}
      <div class="text-cold-light text-sm">Buscando…</div>
    {:else if query.trim().length >= 2 && !searchError}
      <div class="text-cold-light text-sm">Sin resultados en Spotify.</div>
    {/if}

    <!-- Manual fallback: songs not on Spotify. -->
    <div class="mt-2">
      <button type="button" on:click={() => (manualOpen = !manualOpen)} class="text-cold-light text-sm underline">
        ¿No está en Spotify? Agrégala manualmente
      </button>
      {#if manualOpen}
        <div class="mt-3 flex flex-col gap-2 bg-base-900 rounded-lg p-3">
          <input type="text" bind:value={mTitle} maxlength="200" placeholder="Título" class="p-2 border rounded-lg" />
          <input type="text" bind:value={mArtist} maxlength="200" placeholder="Artista" class="p-2 border rounded-lg" />
          <button type="button" on:click={addManual} disabled={submitting} class="bg-cold-base text-white rounded-full px-4 py-2 text-sm self-start disabled:opacity-60">
            {submitting ? 'Creando…' : 'Crear canción'}
          </button>
        </div>
      {/if}
    </div>
  </div>
{/if}
