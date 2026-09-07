<!-- Live mode console (#37, Stage 1) — the "run the show" surface.
     One-thumb and low-attention by design: the admin may be on stage. A single
     large Next is ~90% of taps; everything else is secondary.
     The now-playing pointer is DERIVED, not stored: the one performance with
     live_state = 'playing' IS the pointer (see docs/specs/live-mode.md). -->
<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
  import { ChevronLeft, Play, SkipForward, Square, Users, Check, Undo2, Pause } from 'lucide-svelte';

  let partyId = 0;
  let party: any = null;
  let perfs: any[] = [];
  let songsById: Record<number, any> = {};
  let bandsById: Record<number, any> = {};
  let lineupByPerf: Record<number, string[]> = {};
  let usersById: Record<string, any> = {};
  let currentUserId: string | null = null;
  let partyAdmins: string[] = [];
  let loading = true;
  let error: string | null = null;
  let busy = false;
  let unsubscribeUser: () => void;
  let channel: any = null;

  $: canAdmin = !!currentUserId && (party?.created_by === currentUserId || partyAdmins.includes(currentUserId));
  $: ordered = [...perfs].sort((a, b) => (a.order ?? 9999) - (b.order ?? 9999) || a.id - b.id);
  $: nowPlaying = ordered.find((p) => p.live_state === 'playing') ?? null;
  $: upcoming = ordered.filter((p) => p.live_state === 'queued');
  $: donePerfs = ordered.filter((p) => p.live_state === 'played' || p.live_state === 'skipped');
  $: isLive = party?.status === 'live';
  $: isOver = party?.status === 'completed';

  function songTitle(p: any) { return songsById[p.song]?.title ?? 'Canción'; }
  function songArtist(p: any) { return songsById[p.song]?.artist ?? ''; }
  function bandName(p: any) { return p.band_id ? (bandsById[p.band_id]?.name ?? 'Banda') : null; }
  function avatarOf(id: string) { return usersById[id]?.avatarUrl || '/images/avatar-default.svg'; }
  function nicknameOf(id: string) { return usersById[id]?.nickname ?? 'Anónimo'; }

  async function load() {
    const { data: p, error: pe } = await supabase.from('party').select('*').eq('id', partyId).single();
    if (pe || !p) { error = pe?.message ?? 'No se encontró el toque.'; loading = false; return; }
    party = p;
    const { data: admins } = await supabase.from('party_admin').select('user_id').eq('party_id', partyId);
    partyAdmins = (admins ?? []).map((a: any) => a.user_id);
    await loadSetlist();
    loading = false;
  }

  async function loadSetlist() {
    const { data, error: e } = await supabase
      .from('performance')
      .select('id, song, order, band_id, live_state, started_at, ended_at')
      .eq('party', partyId)
      // Same reason as the detail page: physical row order shifts on every
      // UPDATE, and the console updates rows constantly.
      .order('order', { ascending: true, nullsFirst: false })
      .order('id', { ascending: true });
    if (e) { error = e.message; return; }
    perfs = data ?? [];
    const songIds = [...new Set(perfs.map((p) => p.song).filter(Boolean))] as number[];
    const bandIds = [...new Set(perfs.map((p) => p.band_id).filter(Boolean))] as number[];
    const [songsRes, bandsRes, puRes] = await Promise.all([
      songIds.length ? supabase.from('song').select('id, title, artist').in('id', songIds) : Promise.resolve({ data: [] as any[] }),
      bandIds.length ? supabase.from('band').select('id, name').in('id', bandIds) : Promise.resolve({ data: [] as any[] }),
      perfs.length ? supabase.from('performance_user').select('performance_id, user_id, status').in('performance_id', perfs.map((p) => p.id)) : Promise.resolve({ data: [] as any[] })
    ]);
    songsById = Object.fromEntries((songsRes.data ?? []).map((s: any) => [s.id, s]));
    bandsById = Object.fromEntries((bandsRes.data ?? []).map((b: any) => [b.id, b]));
    const lineup: Record<number, string[]> = {};
    for (const r of puRes.data ?? []) {
      if (r.status !== 'approved') continue;
      const arr = (lineup[r.performance_id] ??= []);
      if (!arr.includes(r.user_id)) arr.push(r.user_id);
    }
    lineupByPerf = lineup;
    const ids = [...new Set(Object.values(lineup).flat())];
    if (ids.length) {
      const { data: profs } = await supabase.from('profile').select('id, nickname, avatarUrl: avatar_url').in('id', ids);
      usersById = Object.fromEntries((profs ?? []).map((u: any) => [u.id, u]));
    }
  }

  // One RPC per action, so the multi-row change (close the current song, open the
  // next) is atomic and can never leave two songs playing. The call is passed in
  // rather than an RPC name, so each keeps its generated argument types.
  async function exec(call: () => PromiseLike<{ error: any }>, okMsg?: string) {
    if (busy) return;
    busy = true;
    try {
      const { error: e } = await call();
      if (e) {
        // 23505 on performance_one_playing_per_party means another admin tapped
        // Next at the same moment and won. That's the invariant doing its job,
        // not a failure — the show is fine, this client is just behind. Resync
        // quietly rather than alarming someone who is on stage.
        if ((e as any).code === '23505') { await load(); return; }
        reportError(e);
        return;
      }
      await load();
      if (okMsg) toastSuccess(okMsg);
    } catch {
      toastError('No se pudo conectar con el servidor.');
    } finally {
      busy = false;
    }
  }

  // Stage 2 — the messy-reality controls. Every one is correctable.
  const skip        = () => exec(() => supabase.rpc('skip_song', { p_party: partyId }), 'Canción saltada.');
  const takeABreak  = () => exec(() => supabase.rpc('end_current_song', { p_party: partyId }), 'Pausa — nada sonando.');
  const undo        = () => exec(() => supabase.rpc('undo_last_move', { p_party: partyId }), 'Listo, volvimos atrás.');
  const jumpTo      = (id: number) => exec(() => supabase.rpc('jump_to_song', { p_party: partyId, p_performance: id }));

  // Nothing has finished yet => nothing to undo. Keeps the button honest rather
  // than letting the RPC raise at someone mid-show.
  $: canUndo = donePerfs.length > 0;

  onMount(async () => {
    unsubscribeUser = user.subscribe((u) => { currentUserId = u?.id ?? null; });
    partyId = Number(page.params.id);
    await load();
    // Another admin advancing, or a song added mid-show, refreshes this console.
    channel = supabase
      .channel('live-console-' + partyId)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'performance', filter: 'party=eq.' + partyId }, () => { if (!busy) loadSetlist(); })
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'party', filter: 'id=eq.' + partyId }, (payload: any) => { if (!busy) party = { ...party, ...payload.new }; })
      .subscribe();
  });

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser();
    if (channel) supabase.removeChannel(channel);
  });
</script>

<div class="min-h-screen bg-base-950">
  <div class="flex items-center gap-2 px-4 py-3">
    <a href={'/parties/' + page.params.id} class="text-cold-light hover:text-white inline-flex items-center"><ChevronLeft />VOLVER</a>
  </div>

  {#if loading}
    <div class="p-6 text-white">Cargando…</div>
  {:else if error}
    <div class="p-6 text-red-500">Error: {error}</div>
  {:else if !canAdmin}
    <div class="mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
      Solo los administradores del toque pueden dirigir el show.
    </div>
  {:else}
    <div class="px-4 pb-32 flex flex-col gap-4">
      <div class="flex items-baseline gap-3 flex-wrap">
        <h1 class="text-2xl text-yellow font-medium">{party.title}</h1>
        {#if isLive}
          <span class="inline-flex items-center gap-1.5 text-xs uppercase tracking-wide text-warm-base">
            <span class="w-2 h-2 rounded-full bg-warm-base animate-pulse"></span> En vivo
          </span>
        {/if}
      </div>

      {#if isOver}
        <div class="bg-base-900 rounded-lg p-6 flex flex-col gap-3 items-start">
          <p class="text-white">El show terminó. Sonaron {donePerfs.length} de {ordered.length} canciones.</p>
          <a href={'/parties/' + page.params.id} class="text-cold-light underline text-sm">Ver el toque</a>
          <!-- The main controls live in the bottom bar, which only renders while
               the show is live — so ending by mistake would otherwise be a dead
               end. undo_last_move puts the toque back on the air. -->
          {#if canUndo}
            <button type="button" on:click={undo} disabled={busy}
                    class="mt-1 text-cold-light hover:text-white text-sm border border-cold-light/30 hover:border-cold-light rounded-lg px-3 py-1.5 inline-flex items-center gap-2 transition disabled:opacity-40">
              <Undo2 size={15} /> ¿Lo terminaste sin querer? Volver atrás
            </button>
          {/if}
        </div>
      {:else if !isLive}
        <div class="bg-base-900 rounded-lg p-6 flex flex-col gap-4">
          <div>
            <h2 class="text-white text-lg">Todo listo para empezar</h2>
            <p class="text-cold-light text-sm mt-1">
              {ordered.length} {ordered.length === 1 ? 'canción' : 'canciones'} en el setlist. Al empezar avisamos a los músicos inscritos y arranca la primera.
            </p>
          </div>
          <button on:click={() => exec(() => supabase.rpc('start_show', { p_party: partyId }), '¡Arrancó el show!')} disabled={busy || !ordered.length}
                  class="bg-cold-base hover:bg-cold-light hover:text-black text-white rounded-lg px-6 py-4 text-lg inline-flex items-center justify-center gap-2 transition disabled:opacity-50">
            <Play size={22} /> {busy ? 'Empezando…' : 'Empezar el show'}
          </button>
        </div>
      {:else}
        <div class="rounded-lg overflow-clip border border-warm-base/40">
          <div class="bg-base-900 px-4 py-3">
            <span class="text-xs uppercase tracking-widest text-warm-base">Sonando ahora</span>
            {#if nowPlaying}
              <div class="mt-1">
                <div class="text-2xl text-yellow leading-tight">{songTitle(nowPlaying)}</div>
                <div class="text-cold-light">{songArtist(nowPlaying)}</div>
                {#if bandName(nowPlaying)}
                  <div class="mt-2 text-sm text-white inline-flex items-center gap-1.5"><Users size={14} /> {bandName(nowPlaying)}</div>
                {/if}
                {#if lineupByPerf[nowPlaying.id]?.length}
                  <div class="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1.5">
                    {#each lineupByPerf[nowPlaying.id] as uid (uid)}
                      <span class="inline-flex items-center gap-1.5">
                        <img src={avatarOf(uid)} alt="" class="w-6 h-6 rounded-full border border-cold-base" />
                        <span class="text-cold-light text-xs">{nicknameOf(uid)}</span>
                      </span>
                    {/each}
                  </div>
                {/if}
              </div>
            {:else}
              <div class="mt-1 text-white">Entre canciones — toca Siguiente para arrancar la próxima.</div>
            {/if}
          </div>
          {#if nowPlaying}
            <div class="bg-base-950 px-4 py-2 flex items-center gap-4 border-t border-base-900">
              <button type="button" on:click={skip} disabled={busy}
                      class="text-cold-light hover:text-white text-sm inline-flex items-center gap-1.5 disabled:opacity-40">
                <SkipForward size={15} /> Saltar
              </button>
              <button type="button" on:click={takeABreak} disabled={busy}
                      class="text-cold-light hover:text-white text-sm inline-flex items-center gap-1.5 disabled:opacity-40">
                <Pause size={15} /> Pausa
              </button>
            </div>
          {/if}
        </div>

        <div class="flex flex-col gap-2">
          <span class="text-xs uppercase tracking-widest text-cold-light">
            {upcoming.length ? 'Faltan ' + upcoming.length + ' · toca una para saltar ahí' : 'No queda nada por tocar'}
          </span>
          {#if upcoming.length}
            <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
              {#each upcoming as p, i (p.id)}
                <li class="bg-base-900">
                  <button type="button" on:click={() => jumpTo(p.id)} disabled={busy}
                          class="w-full text-left px-4 py-3 flex items-center gap-3 hover:bg-base-950 transition disabled:opacity-60">
                    <span class="text-gray-400 text-xl w-6 shrink-0">{i + 1}</span>
                    <div class="min-w-0 flex-1">
                      <div class="text-yellow truncate">{songTitle(p)}</div>
                      <div class="text-sm text-cold-light truncate">
                        {songArtist(p)}{#if bandName(p)} · {bandName(p)}{/if}
                      </div>
                    </div>
                  </button>
                </li>
              {/each}
            </ul>
          {/if}
        </div>

        {#if donePerfs.length}
          <details class="rounded-lg bg-base-900 px-4 py-3">
            <summary class="text-cold-light text-sm cursor-pointer">Ya sonaron · {donePerfs.length}</summary>
            <p class="text-cold-light/50 text-xs mt-1">Toca una para repetirla — un bis, o si te adelantaste.</p>
            <ul class="mt-2 flex flex-col gap-1">
              {#each donePerfs as p (p.id)}
                <li>
                  <button type="button" on:click={() => jumpTo(p.id)} disabled={busy}
                          class="w-full text-left text-sm flex items-center gap-2 py-1 hover:text-white transition disabled:opacity-40 {p.live_state === 'skipped' ? 'text-cold-light/40' : 'text-cold-light/70'}">
                    {#if p.live_state === 'skipped'}
                      <SkipForward size={14} class="shrink-0" />
                    {:else}
                      <Check size={14} class="text-green-500 shrink-0" />
                    {/if}
                    <span class="truncate">{songTitle(p)}</span>
                    {#if p.live_state === 'skipped'}<span class="text-xs shrink-0">saltada</span>{/if}
                  </button>
                </li>
              {/each}
            </ul>
          </details>
        {/if}
      {/if}
    </div>

    <!-- The workhorse, pinned where a thumb already is. -->
    {#if isLive}
      <div class="fixed bottom-0 inset-x-0 bg-base-950/95 border-t border-base-900 p-4 flex items-center gap-3">
        <button on:click={undo} disabled={busy || !canUndo} aria-label="Volver a la anterior" title="Volver a la anterior"
                class="text-cold-light hover:text-white border border-cold-light/30 hover:border-cold-light rounded-lg px-4 py-5 transition disabled:opacity-30 shrink-0">
          <Undo2 size={20} />
        </button>
        <button on:click={() => exec(() => supabase.rpc('advance_show', { p_party: partyId }))} disabled={busy}
                class="flex-1 bg-cold-base hover:bg-cold-light hover:text-black text-white rounded-lg px-6 py-5 text-xl inline-flex items-center justify-center gap-3 transition disabled:opacity-50">
          <SkipForward size={26} /> {upcoming.length ? 'Siguiente' : 'Terminar la última'}
        </button>
        <button on:click={() => exec(() => supabase.rpc('end_show', { p_party: partyId }), 'Show terminado.')} disabled={busy}
                aria-label="Terminar el show"
                class="text-red-400 hover:text-red-300 border border-red-400/40 hover:border-red-300 rounded-lg px-4 py-5 transition disabled:opacity-50">
          <Square size={20} />
        </button>
      </div>
    {/if}
  {/if}
</div>
