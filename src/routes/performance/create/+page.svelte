<script lang="ts">
    import { ChevronLeft, X, Users, Check, ExternalLink } from 'lucide-svelte';
    import { goto } from '$app/navigation';
    import { onMount, onDestroy, tick } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { page } from '$app/state';
    import { user } from '$lib/stores/user';
    import SongSelect from '$lib/components/SongSelect.svelte';
    import { reportError, toastError, toastInfo, toastSuccess } from '$lib/stores/toasts';
    import { tidySpotifyResults } from '$lib/spotify';
    import { normalizeText } from '$lib/sanitize';

    let songs: any[] = [];
    let errorSongs: string | null = null;
    let partyId: string | null = null;
    let userId: string | null = null;
    let songSearch = '';
    let isAuthenticated = false;
    let unsubscribeUser: () => void;
    let adding = false;
    // Songs added this session (#77) — newest first. { perfId, songId, title, artist, band }
    let added: any[] = [];
    // Sign up as a band (#73): '' = open jam; otherwise a band id. Set ONCE, applies
    // to every song added this session (#77) — the win for a band's setlist.
    let signupChoice = '';
    let bandsLoaded = false;
    let partyIsTest = false;
    let partyLoaded = false;
    // What's ALREADY on this party's setlist, keyed by song id. Loaded once so a
    // repeat is a visible choice rather than a surprise — someone else may have
    // added the song, or you may have added it on an earlier visit (`added` only
    // covers this session). Repeats stay allowed: two bands covering the same
    // song, or an encore, are legitimate calls that belong to the organizer.
    let existing: Record<string, { count: number; bands: string[] }> = {};

    async function loadExisting(pid: string) {
      const { data } = await supabase.from('performance').select('song, band_id').eq('party', Number(pid));
      if (!data) return;
      const bandIds = [...new Set(data.map((r: any) => r.band_id).filter(Boolean))];
      const { data: bands } = bandIds.length
        ? await supabase.from('band').select('id, name').in('id', bandIds)
        : { data: [] as any[] };
      const bandName: Record<string, string> = {};
      for (const b of bands ?? []) bandName[b.id] = b.name;
      const map: Record<string, { count: number; bands: string[] }> = {};
      for (const r of data as any[]) {
        if (r.song == null) continue;
        const e = (map[r.song] ??= { count: 0, bands: [] });
        e.count += 1;
        const n = r.band_id ? bandName[r.band_id] : null;
        if (n && !e.bands.includes(n)) e.bands.push(n);
      }
      existing = map;
    }

    // Badge text per song id for the search results. Session adds and pre-existing
    // entries read differently because they behave differently (see addSong).
    $: notes = (() => {
      const n: Record<string, string> = {};
      for (const [songId, e] of Object.entries(existing)) {
        n[songId] = e.bands.length
          ? `Ya en el setlist · ${e.bands.join(', ')}`
          : e.count > 1
            ? `Ya en el setlist ×${e.count}`
            : 'Ya en el setlist';
      }
      for (const a of added) n[a.songId] = 'La agregaste hace un momento';
      return n;
    })();

    // Raw rows, filtered reactively. The FETCH never needed partyIsTest — only the
    // filter did — so waiting for the party row before asking for bands put a
    // needless round trip in series (#87, see #84).
    let myBandRows: any[] = [];
    async function loadMyBandRows(uid: string) {
      const { data } = await supabase
        .from('band_member')
        .select('role, band ( id, name, who_can_sign_up, is_test )')
        .eq('user_id', uid);
      myBandRows = data ?? [];
    }
    $: myBands = myBandRows
      .filter((r: any) => r.band && (r.band.who_can_sign_up === 'members' || r.role === 'manager'))
      // A test band can't play a real event (RLS/RPC enforce it too) — hide the option (#76).
      .filter((r: any) => partyIsTest || !r.band.is_test)
      .map((r: any) => ({ id: r.band.id, name: r.band.name }));
    // No longer gated on partyLoaded: this now races the party fetch instead of
    // queueing behind it.
    $: if (userId && !bandsLoaded) { bandsLoaded = true; loadMyBandRows(userId); }

    onMount(async () => {
      unsubscribeUser = user.subscribe(u => {
        isAuthenticated = !!u?.id;
        userId = u?.id ?? null;
      });
      partyId = page.url.searchParams.get('partyId') ?? null;
      if (partyId) {
        // Independent of each other: one wave, not two.
        const [partyRes] = await Promise.all([
          supabase.from('party').select('is_test').eq('id', Number(partyId)).maybeSingle(),
          loadExisting(partyId)
        ]);
        partyIsTest = partyRes.data?.is_test ?? false;
      }
      partyLoaded = true;
    });

    onDestroy(() => { if (unsubscribeUser) unsubscribeUser(); });

    // Ranked song search (#82): a server-side RPC ranks BEFORE limiting and
    // matches each term across title+artist (so "One", "one metallica" and "u2"
    // all work). Debounced with a latest-wins guard against out-of-order results.
    let searchSeq = 0;
    let searchTimer: any = null;
    // On phones the keyboard covers the suggestions. Rather than repositioning the
    // field (which breaks the layout and snaps back), scroll the PAGE so the field
    // sits at the top of the viewport — it stays put across focus/blur. `spacerH`
    // grows only as much as needed for the page to be able to scroll that far.
    let searchWrap: HTMLElement;
    let spacerH = 0;

    async function pinSearchToTop() {
      if (typeof window === 'undefined' || window.innerWidth >= 768) return; // desktop has room
      // Let the keyboard finish opening (it changes the visible viewport).
      setTimeout(async () => {
        if (!searchWrap) return;
        // NB: the field must NOT be sticky — a stuck element reports rect.top 0,
        // which would make this read its own scroll offset instead of its place
        // in the document.
        // Reserve one viewport of extra room. Any element is then guaranteed to be
        // scrollable to the top, with no height arithmetic to get wrong. Set once
        // and never changed, so it can't cause a jump on blur/add.
        if (!spacerH) {
          spacerH = window.innerHeight;
          await tick();
        }
        const top = searchWrap.getBoundingClientRect().top + window.scrollY;
        window.scrollTo({ top, behavior: 'smooth' });
      }, 250);
    }
    $: scheduleSearch(songSearch);
    function scheduleSearch(q: string) {
      clearTimeout(searchTimer);
      const query = (q ?? '').trim();
      searchedTerm = '';
      if (query.length < 2) { songs = []; return; }
      searchTimer = setTimeout(() => runSearch(query), 250);
    }
    // Which term `songs` actually corresponds to. Needed because the local
    // search is debounced and async: without it, anything keyed on `songs`
    // reads an empty list for every new term before the results land.
    let searchedTerm = '';
    async function runSearch(query: string) {
      const seq = ++searchSeq;
      const { data, error } = await supabase.rpc('search_songs', { q: query, lim: 20 });
      if (seq !== searchSeq) return; // a newer search superseded this one
      if (error) { errorSongs = error.message; songs = []; searchedTerm = query; return; }
      songs = data ?? [];
      errorSongs = null;
      searchedTerm = query;
    }

    // ---- Spotify, in place (#98) -------------------------------------------
    // Adding a song that is not in the catalogue used to mean leaving for
    // /songs/create and searching the SAME song three times, landing back on an
    // empty page with the song still not on the setlist. The edge function
    // already does search (#83), so the whole thing collapses to: search here,
    // resolve a song id on tap, and hand it to addSong.
    //
    // Only when the local search finds NOTHING does this fire automatically —
    // that is exactly the "no encuentro mi canción" moment, and it keeps the
    // edge function out of the common case where the ~6.5k-song catalogue hits.
    const SPOTIFY_LIMIT = 5;   // a longer list pushes "Agregadas" off a phone
    let spotifyResults: any[] = [];
    let spotifySearching = false;
    let spotifyError = '';
    let spotifySeq = 0;
    // Set when the user asks for it explicitly despite having local results.
    let spotifyRequested = false;

    async function searchSpotify(term: string) {
      const seq = ++spotifySeq;
      spotifyError = '';
      spotifySearching = true;
      try {
        const { data, error } = await supabase.functions.invoke('spotify-track', { body: { q: term } });
        if (seq !== spotifySeq) return;                  // superseded
        if (error || (data as any)?.error) { spotifyError = 'No se pudo buscar en Spotify.'; spotifyResults = []; return; }
        spotifyResults = tidySpotifyResults((data as any).results ?? []).slice(0, SPOTIFY_LIMIT);
      } catch {
        if (seq === spotifySeq) { spotifyError = 'No se pudo conectar con el servidor.'; spotifyResults = []; }
      } finally {
        if (seq === spotifySeq) spotifySearching = false;
      }
    }

    // Auto only on an empty local result set; the manual trigger sets
    // spotifyRequested. `songs` and `songSearch` are named so legacy mode tracks
    // them — a helper reading them internally would never re-run.
    // Only once the LOCAL search has resolved for this exact term. Keying on
    // `songs` alone raced the debounce: songs is [] for a moment on every
    // keystroke, so Spotify fired for queries that had perfectly good local hits.
    $: {
      const term = (songSearch ?? '').trim();
      if (term.length < 2) {
        spotifyResults = []; spotifyRequested = false; spotifyError = '';
      } else if (searchedTerm === term && (songs.length === 0 || spotifyRequested)) {
        searchSpotify(term);
      } else if (searchedTerm !== term) {
        spotifyResults = [];   // results belong to the previous term
      }
    }

    // Reuse an existing song by its Spotify link, else insert one. ref_link has a
    // UNIQUE constraint, so a concurrent insert of the same track surfaces as
    // 23505 — re-select rather than failing the tap.
    async function resolveSongId(r: any): Promise<{ id: number; title: string; artist: string } | null> {
      const title = normalizeText(r.title, 200);
      const artist = normalizeText(r.artist, 200);
      const ref_link = r.spotify_url ?? null;
      if (ref_link) {
        const { data: existing } = await supabase.from('song').select('id').eq('ref_link', ref_link).maybeSingle();
        if (existing) return { id: existing.id, title, artist };
      }
      const { data, error } = await supabase.from('song').insert([{
        title, artist, ref_link, added_by: userId,
        // song.duration is decimal MINUTES (the catalogue's convention); the
        // function gives seconds.
        ...(r.duration_s ? { duration: Math.round((r.duration_s / 60) * 100) / 100 } : {})
      }]).select('id');
      if (error) {
        if ((error as any).code === '23505' && ref_link) {
          const { data: raced } = await supabase.from('song').select('id').eq('ref_link', ref_link).maybeSingle();
          if (raced) return { id: raced.id, title, artist };
        }
        reportError(error);
        return null;
      }
      return data?.[0] ? { id: data[0].id, title, artist } : null;
    }

    async function addFromSpotify(r: any) {
      if (adding) return;
      adding = true;
      const song = await resolveSongId(r);
      adding = false;
      if (!song) return;
      // Straight into the normal path, so a Spotify pick gets the same duplicate
      // guards, band signup and "Agregadas" entry a local pick does. Resolving by
      // ref_link can return a song that is ALREADY on this setlist.
      await addSong(song);
    }

    // Tap a search result → add it right away (incremental, #77).
    async function addSong(song: any) {
      if (!partyId || !userId || adding) return;
      // Added seconds ago and sitting right below — a second tap is a mis-tap, so
      // block it. A song already on the setlist from BEFORE this session is a
      // different case: it's badged in the results and the tap goes through.
      if (added.some((a) => a.songId === song.id)) { toastInfo('Ya la agregaste.'); return; }
      const timesAlready = existing[song.id]?.count ?? 0;
      adding = true;
      try {
        const { data, error } = await supabase
          .from('performance')
          .insert([{ party: Number(partyId), song: Number(song.id), suggested_by: userId }])
          .select('id');
        if (error) { reportError(error); return; }
        const perfId = data?.[0]?.id;
        let band: any = null;
        if (signupChoice && perfId) {
          const { error: rpcErr } = await supabase.rpc('sign_band_up', { p_performance: perfId, p_band: Number(signupChoice) });
          if (rpcErr) {
            reportError(rpcErr);
            await supabase.from('performance').delete().eq('id', perfId); // roll back the orphan
            return;
          }
          band = myBands.find((b) => b.id === Number(signupChoice)) ?? null;
        }
        added = [{ perfId, songId: song.id, title: song.title, artist: song.artist, band }, ...added];
        if (timesAlready) toastInfo(`Quedó ${timesAlready + 1} veces en el setlist.`);
      } catch {
        toastError('No se pudo conectar con el servidor.');
      } finally {
        adding = false;
      }
    }

    async function removeAdded(item: any) {
      const { error } = await supabase.from('performance').delete().eq('id', item.perfId);
      if (error) { reportError(error); return; }
      added = added.filter((a) => a.perfId !== item.perfId);
    }

    function done() { goto(`/parties/${partyId}#setlist`); }

    function loginWithGoogle() {
      supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.href } });
    }
</script>

<a href={partyId ? `/parties/${partyId}#setlist` : '/parties'} class="text-bold text-cold-light flex flex-row px-4"><ChevronLeft />VOLVER</a>
<h2 class="text-yellow text-2xl px-5 py-2">AGREGA CANCIONES AL SETLIST</h2>

{#if !isAuthenticated}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para agregar canciones al Setlist.
  </div>
{:else}
  <!-- padding-bottom gives the page just enough room to scroll the search field
       to the top on mobile (see pinSearchToTop); 0 on desktop. -->
  <div class="flex flex-col w-full p-4 gap-4" style="padding-bottom:{16 + spacerH}px">
    {#if myBands.length}
      <div class="flex flex-col gap-1">
        <label for="signup" class="text-cold-light text-sm">¿Quién las toca?</label>
        <select id="signup" bind:value={signupChoice} class="p-2 border rounded-lg">
          <option value="">Ábrela — cualquiera se suma</option>
          {#each myBands as b}
            <option value={b.id}>La toca {b.name}</option>
          {/each}
        </select>
        <span class="text-cold-light/60 text-xs">Se aplica a cada canción que agregues.</span>
      </div>
    {/if}

    <!-- Stays in normal flow (never repositioned) so the layout can't break; on
         focus the PAGE scrolls this to the top so the keyboard can't cover the
         results. Don't make this sticky — see pinSearchToTop. -->
    <div bind:this={searchWrap} class="flex flex-col gap-1">
      <span class="text-cold-light text-sm">Busca y toca una canción para agregarla</span>
      <SongSelect {songs} {notes} bind:value={songSearch} multiAdd serverFiltered
        on:select={(e) => addSong(e.detail)}
        on:focus={pinSearchToTop} />
      {#if errorSongs}<div class="text-red-500 text-sm">{errorSongs}</div>{/if}

      <!-- Spotify results (#98). A SEPARATE group, never mixed into the local
           ones: tapping here adds a song to the shared catalogue for everyone,
           and the UI should not hide that. The logo + wording is Spotify's
           attribution requirement, not decoration — same markup as
           /songs/create. -->
      {#if spotifySearching}
        <div class="text-cold-light text-sm">Buscando en Spotify…</div>
      {:else if spotifyError}
        <div class="text-red-500 text-sm">{spotifyError}</div>
      {:else if spotifyResults.length}
        <div class="flex flex-col gap-2">
          <span class="text-xs text-cold-light/70 inline-flex items-center gap-1">
            <img src="/images/spotify-logo.svg" alt="Spotify" class="h-3"
              on:error={(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')} /> Resultados de Spotify
          </span>
          <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip p-0">
            {#each spotifyResults as r}
              <li class="bg-base-900 flex items-center gap-1 pr-2">
                <button type="button" on:click={() => addFromSpotify(r)} disabled={adding}
                  class="flex-1 min-w-0 hover:bg-base-950 transition px-3 py-2 flex items-center gap-3 text-left disabled:opacity-60">
                  {#if r.art_url}<img src={r.art_url} alt="" class="w-11 h-11 rounded object-cover shrink-0" />{/if}
                  <div class="min-w-0 flex-1">
                    <div class="text-yellow truncate">{r.title}</div>
                    <div class="text-sm text-cold-light truncate">{r.artist}</div>
                  </div>
                </button>
                <a href={r.spotify_url} target="_blank" rel="noopener"
                  class="text-cold-light/60 hover:text-cold-light shrink-0 p-1" aria-label="Abrir en Spotify"><ExternalLink size={15} /></a>
              </li>
            {/each}
          </ul>
        </div>
      {:else if songs.length && searchedTerm === (songSearch ?? '').trim() && !spotifyRequested}
        <!-- Local hits exist but none is right: offer the search rather than
             firing it, so the common case costs no edge-function call. -->
        <button type="button" on:click={() => (spotifyRequested = true)}
          class="text-cold-light text-sm underline self-start">¿No está? Búscala en Spotify</button>
      {/if}
    </div>

    {#if added.length}
      <div class="flex flex-col gap-2">
        <span class="text-white text-sm">Agregadas · {added.length}</span>
        <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
          {#each added as item (item.perfId)}
            <li class="bg-base-900 px-4 py-3 flex items-center justify-between gap-3">
              <div class="min-w-0">
                <div class="text-yellow truncate">{item.title}</div>
                <div class="text-sm text-cold-light truncate flex items-center gap-1">
                  {item.artist}
                  {#if item.band}<span class="text-cold-light/70 inline-flex items-center gap-1">· <Users size={12} /> {item.band.name}</span>{/if}
                </div>
              </div>
              <button type="button" on:click={() => removeAdded(item)} aria-label="Quitar" class="text-red-400 hover:text-red-300 p-1 shrink-0"><X size={18} /></button>
            </li>
          {/each}
        </ul>
      </div>
    {/if}

    <button type="button" on:click={done} class="bg-cold-base text-white rounded-full px-6 py-2 self-center inline-flex items-center gap-2">
      <Check size={18} /> {added.length ? 'Listo — ver toque' : 'Volver al toque'}
    </button>
  </div>

  <p class="mt-2 mb-8 text-center text-cold-light text-sm">
    Si no está en Spotify, <a href="/songs/create" class="text-cold-light underline">agrégala a mano</a>.
  </p>
{/if}
