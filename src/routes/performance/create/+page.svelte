<script lang="ts">
    import { ChevronLeft, X, Users, Check } from 'lucide-svelte';
    import { goto } from '$app/navigation';
    import { onMount, onDestroy, tick } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { page } from '$app/state';
    import { user } from '$lib/stores/user';
    import SongSelect from '$lib/components/SongSelect.svelte';
    import { reportError, toastError, toastInfo } from '$lib/stores/toasts';

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
    let myBands: { id: number; name: string }[] = [];
    let signupChoice = '';
    let bandsLoaded = false;
    let partyIsTest = false;
    let partyLoaded = false;

    async function loadMyBands(uid: string) {
      const { data } = await supabase
        .from('band_member')
        .select('role, band ( id, name, who_can_sign_up, is_test )')
        .eq('user_id', uid);
      myBands = (data ?? [])
        .filter((r: any) => r.band && (r.band.who_can_sign_up === 'members' || r.role === 'manager'))
        // A test band can't play a real event (RLS/RPC enforce it too) — hide the option (#76).
        .filter((r: any) => partyIsTest || !r.band.is_test)
        .map((r: any) => ({ id: r.band.id, name: r.band.name }));
    }
    $: if (userId && partyLoaded && !bandsLoaded) { bandsLoaded = true; loadMyBands(userId); }

    onMount(async () => {
      unsubscribeUser = user.subscribe(u => {
        isAuthenticated = !!u?.id;
        userId = u?.id ?? null;
      });
      partyId = page.url.searchParams.get('partyId') ?? null;
      if (partyId) {
        const { data } = await supabase.from('party').select('is_test').eq('id', Number(partyId)).maybeSingle();
        partyIsTest = data?.is_test ?? false;
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
      if (query.length < 2) { songs = []; return; }
      searchTimer = setTimeout(() => runSearch(query), 250);
    }
    async function runSearch(query: string) {
      const seq = ++searchSeq;
      const { data, error } = await supabase.rpc('search_songs', { q: query, lim: 20 });
      if (seq !== searchSeq) return; // a newer search superseded this one
      if (error) { errorSongs = error.message; songs = []; return; }
      songs = data ?? [];
      errorSongs = null;
    }

    // Tap a search result → add it right away (incremental, #77).
    async function addSong(song: any) {
      if (!partyId || !userId || adding) return;
      if (added.some((a) => a.songId === song.id)) { toastInfo('Ya está en la lista.'); return; }
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

    function done() { goto(`/parties/${partyId}`); }

    function loginWithGoogle() {
      supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.href } });
    }
</script>

<a href={partyId ? `/parties/${partyId}` : '/parties'} class="text-bold text-cold-light flex flex-row px-4"><ChevronLeft />VOLVER</a>
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
      <SongSelect {songs} bind:value={songSearch} multiAdd serverFiltered
        on:select={(e) => addSong(e.detail)}
        on:focus={pinSearchToTop} />
      {#if errorSongs}<div class="text-red-500 text-sm">{errorSongs}</div>{/if}
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

  <p class="mt-2 mb-8 text-center text-cold-light">
    ¿No encuentras tu canción en la lista? <a href="/songs/create?from=performance&partyId={partyId}" class="text-cold-light underline">Agrégala aquí</a>.
  </p>
{/if}
