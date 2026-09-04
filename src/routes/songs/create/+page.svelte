<script lang="ts">
    import { ArrowLeft, Search, ExternalLink, Check } from 'lucide-svelte';
    import { goto } from '$app/navigation';
    import { onMount, onDestroy } from 'svelte';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import { page } from '$app/stores';
    import { supabase } from '$lib/supabaseClient';
    import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
    import { normalizeText } from '$lib/sanitize';

    let userId: string | null = null;
    let isAuthenticated = false;
    let unsubscribeUser: () => void;
    let fromPerformance = false;
    let partyId: string | null = null;

    // Spotify import (#80)
    let link = '';
    let looking = false;
    let lookupError = '';
    let preview: { title: string; artist: string; art_url: string | null; spotify_url: string } | null = null;
    let submitting = false;

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
    onDestroy(() => { if (unsubscribeUser) unsubscribeUser(); });

    function continueFlow() {
      setTimeout(() => {
        if (fromPerformance && partyId) goto(`/performance/create?partyId=${partyId}`);
        else goto('/songs');
      }, 500);
    }

    async function lookup() {
      lookupError = '';
      preview = null;
      const url = link.trim();
      if (!/open\.spotify\.com\/.*track\/|spotify:track:/.test(url)) {
        lookupError = 'Pega un enlace de canción de Spotify.';
        return;
      }
      looking = true;
      try {
        const { data, error } = await supabase.functions.invoke('spotify-track', { body: { url } });
        if (error) { lookupError = 'No se pudo leer la canción. Revisa el enlace o intenta de nuevo.'; return; }
        if ((data as any)?.error) { lookupError = (data as any).message ?? 'No se encontró la canción.'; return; }
        preview = {
          title: (data as any).title,
          artist: (data as any).artist,
          art_url: (data as any).art_url,
          spotify_url: (data as any).spotify_url
        };
      } catch {
        lookupError = 'No se pudo conectar con el servidor.';
      } finally {
        looking = false;
      }
    }

    // Reuse an existing song (by Spotify link, else title+artist) or insert a new one,
    // then continue. Returns nothing; drives navigation.
    async function insertOrReuse(row: { title: string; artist: string; ref_link: string | null }) {
      submitting = true;
      try {
        if (row.ref_link) {
          const { data: existing } = await supabase.from('song').select('id').eq('ref_link', row.ref_link).maybeSingle();
          if (existing) { toastSuccess('Esa canción ya estaba en la app.'); continueFlow(); return; }
        }
        const { error } = await supabase.from('song').insert([{ title: row.title, artist: row.artist, ref_link: row.ref_link, added_by: userId }]);
        if (error) {
          // Unique violation (ref_link or title+artist): it already exists — reuse.
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

    function addFromSpotify() {
      if (!preview) return;
      insertOrReuse({ title: normalizeText(preview.title, 200), artist: normalizeText(preview.artist, 200), ref_link: preview.spotify_url });
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
    <p class="text-cold-light text-sm">Busca la canción en Spotify y pega su enlace — así queda con el título y artista correctos.</p>

    <a href="https://open.spotify.com/search" target="_blank" rel="noopener"
       class="self-start inline-flex items-center gap-2 border border-cold-light/40 text-cold-light rounded-full px-4 py-2 text-sm hover:border-cold-light">
      <Search size={16} /> Buscar en Spotify <ExternalLink size={14} />
    </a>

    <div class="flex flex-col gap-2">
      <label for="spotify-link" class="text-cold-light text-sm">Enlace de Spotify</label>
      <div class="flex gap-2">
        <input id="spotify-link" type="text" bind:value={link} on:keydown={(e) => e.key === 'Enter' && lookup()}
               placeholder="https://open.spotify.com/track/…" class="flex-1 p-2 border rounded-lg" />
        <button type="button" on:click={lookup} disabled={looking} class="bg-cold-base text-white rounded-lg px-4 disabled:opacity-60">
          {looking ? '…' : 'Buscar'}
        </button>
      </div>
      {#if lookupError}<div class="text-red-500 text-sm">{lookupError}</div>{/if}
    </div>

    {#if preview}
      <div class="bg-base-900 rounded-lg p-3 flex items-center gap-3">
        {#if preview.art_url}
          <img src={preview.art_url} alt="" class="w-16 h-16 rounded object-cover" />
        {/if}
        <div class="min-w-0 flex-1">
          <div class="text-yellow text-lg truncate">{preview.title}</div>
          <div class="text-cold-light truncate">{preview.artist}</div>
          <a href={preview.spotify_url} target="_blank" rel="noopener" class="text-xs text-cold-light/70 inline-flex items-center gap-1 mt-1">
            <img src="/images/spotify-logo.svg" alt="Spotify" class="h-3" on:error={(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')} /> Metadatos de Spotify <ExternalLink size={11} />
          </a>
        </div>
        <button type="button" on:click={addFromSpotify} disabled={submitting} class="bg-cold-base text-white rounded-full px-4 py-2 text-sm inline-flex items-center gap-1 shrink-0 disabled:opacity-60">
          <Check size={16} /> {submitting ? '…' : 'Agregar'}
        </button>
      </div>
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
