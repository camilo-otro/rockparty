<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft, Share2, Trash2, Check, X, ExternalLink, Users } from 'lucide-svelte';
  import { user } from '$lib/stores/user';
  import ShareModal from '$lib/components/ShareModal.svelte';
  import { reportError, toastSuccess, toastInfo, toastError } from '$lib/stores/toasts';

  let performance: any = null;
  let songTitle: string = '';
  let songArtist: string = '';
  let songSpotify: string | null = null; // the song's Spotify link (all songs have one)

  // Deterministic "learn this song" search links (#66) — free, no API/scraping.
  // YouTube needs the ENGLISH term (surfaces far more tutorials) while the
  // instrument table is Spanish. Matched on the NORMALISED name rather than an
  // id, so a re-seed with different ids still resolves.
  function youtubeTermFor(name: string): string | null {
    const n = (name ?? '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '');
    if (n.includes('voz') || n.includes('vocal')) return 'vocals';
    if (n.includes('guitarra') && n.includes('ritmica')) return 'rhythm guitar';
    if (n.includes('guitarra')) return 'lead guitar';
    if (n.includes('bajo')) return 'bass';
    if (n.includes('teclado') || n.includes('piano')) return 'keyboard';
    if (n.includes('bateria') || n.includes('drum')) return 'drums';
    return null;
  }
  $: songQuery = `${songArtist} ${songTitle}`.trim();
  $: ugLink = songQuery ? `https://www.ultimate-guitar.com/search.php?search_type=title&value=${encodeURIComponent(songQuery)}` : null;
  let loading = true;
  let error: string | null = null;
  let suggestedBy: any = null;
  let signingUp = false;
  let instruments: any[] = [];
  let signedUpUsers: any[] = [];
  let showShareModal = false;
  let unsubscribeUser: () => void;
  let currentUserId: string | null = null;
  let party: any = null;
  let partyAdmins: string[] = [];
  // Band-owned song (#74 follow-up): not an open jam — no self-signup / open slots.
  let bandName: string | null = null;
  $: isBand = !!performance?.band_id;

  // How musicians get onto this song (#29). Mirrors the DB trigger so the UI
  // frames the action right; the trigger is the actual enforcement.
  $: mode = party?.performer_approval ?? 'auto';
  $: isPartyAdmin = !!currentUserId && !!party && (currentUserId === party.created_by || partyAdmins.includes(currentUserId));
  $: isProponent = !!currentUserId && !!performance && performance.suggested_by === currentUserId;
  $: autoApprove = mode === 'auto' || isPartyAdmin || (mode === 'proponent' && isProponent);
  $: canSelfSignup = mode !== 'invite_only' || isPartyAdmin || isProponent;
  // An approver is a party admin, or — in proponent mode — this song's proponent.
  $: canApprove = isPartyAdmin || (mode === 'proponent' && isProponent);
  // Participantes: approved musicians, plus the current user's own pending row so
  // an applicant can see (and cancel) their request. Declined rows are shown to
  // their owner below as a re-request affordance, not here.
  $: participants = signedUpUsers.filter((u) => u.status === 'approved' || (u.status === 'pending' && u.user_id === currentUserId));
  $: myDeclined = signedUpUsers.filter((u) => currentUserId && u.user_id === currentUserId && u.status === 'declined');
  // Approver queue: pending applicants grouped by instrument, each group ordered
  // by application time (signedUpUsers is fetched created_at-ascending).
  $: pendingApplicants = signedUpUsers.filter((u) => u.status === 'pending');
  $: groupedPending = groupByInstrument(pendingApplicants);
  // A spot is "taken" once it has an approved player; you can only self-sign-up
  // for open spots (pending applicants still leave a spot open to compete for).
  $: takenInstrumentIds = new Set(signedUpUsers.filter((u) => u.status === 'approved').map((u) => u.instrument_id));
  $: availableInstruments = instruments.filter((i) => !takenInstrumentIds.has(i.id));

  // Tutorials are for whoever committed to play, and only for the instrument they
  // are actually on. Six pills for six instruments read as an instrument chooser —
  // which is exactly what the signup list is — so people tapped the wrong six and
  // ended up on YouTube. Pending counts: you want to start learning while you wait.
  $: myParts = currentUserId
    ? signedUpUsers.filter((u) => u.user_id === currentUserId && (u.status === 'approved' || u.status === 'pending'))
    : [];
  $: myTutorials = myParts
    .map((u) => ({ name: u.instrument as string, term: youtubeTermFor(u.instrument) }))
    .filter((t) => !!t.term && !!songQuery)
    .map((t) => ({
      name: t.name,
      url: `https://www.youtube.com/results?search_query=${encodeURIComponent(`${songQuery} ${t.term} tutorial`)}`
    }));

  function groupByInstrument(rows: any[]): { instrument_id: number; instrument: string; applicants: any[] }[] {
    const map = new Map<number, { instrument_id: number; instrument: string; applicants: any[] }>();
    for (const u of rows) {
      if (!map.has(u.instrument_id)) map.set(u.instrument_id, { instrument_id: u.instrument_id, instrument: u.instrument, applicants: [] });
      map.get(u.instrument_id)!.applicants.push(u);
    }
    return [...map.values()];
  }

  async function fetchSignedUpUsers(performanceId: string) {
    const { data: perfUsers } = await supabase.from('performance_user').select('user_id, instrument_id, status, created_at').eq('performance_id', Number(performanceId)).order('created_at', { ascending: true });
    const users: any[] = [];
    for (const perfUser of perfUsers ?? []) {
      const { data: userData } = await supabase.from('profile').select('nickname').eq('id', perfUser.user_id).single();
      const { data: instrumentData } = await supabase.from('instrument').select('name').eq('id', perfUser.instrument_id).single();
      users.push({
        nickname: userData?.nickname ?? perfUser.user_id,
        instrument: instrumentData?.name ?? '',
        instrument_id: perfUser.instrument_id,
        user_id: perfUser.user_id,
        status: perfUser.status,
        created_at: perfUser.created_at
      });
    }
    return users;
  }

  onMount(async () => {
    unsubscribeUser = user.subscribe(u => {
      currentUserId = u?.id ?? null;
    });
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('performance').select('*').eq('id', Number(id)).single();
    if (err) {
      error = err.message;
    } else {
      performance = data;
      // Fetch song title
      if (performance?.song) {
        const { data: songData } = await supabase.from('song').select('title, artist, ref_link').eq('id', performance.song).single();
        songTitle = songData?.title ?? '';
        songArtist = songData?.artist ?? '';
        songSpotify = songData?.ref_link ?? null;
      }
      // Fetch the parent party's approval mode + admins (drives request framing).
      if (performance?.party) {
        const { data: partyData } = await supabase.from('party').select('id, created_by, performer_approval').eq('id', performance.party).single();
        party = partyData;
        const { data: adminData } = await supabase.from('party_admin').select('user_id').eq('party_id', performance.party);
        partyAdmins = (adminData ?? []).map((a) => a.user_id);
      }
      // Band-owned song: resolve the band name for the label.
      if (performance?.band_id) {
        const { data: bandData } = await supabase.from('band').select('name').eq('id', performance.band_id).maybeSingle();
        bandName = bandData?.name ?? 'una banda';
      }
      // Fetch suggested by user nickname from user table
      if (performance?.suggested_by) {
        const { data: userData } = await supabase.from('profile').select('nickname, avatarUrl: avatar_url').eq('id', performance.suggested_by).single();
        suggestedBy = userData;
      }
      // Fetch signed up users for this performance
      signedUpUsers = await fetchSignedUpUsers(id);
    }
    // Fetch instruments once on mount
    const { data: instrumentData } = await supabase.from('instrument').select('id, name');
    instruments = instrumentData ?? [];
    loading = false;
  });

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser();
  });

  async function refreshSignedUpUsers() {
    if (!performance?.id) return;
    signedUpUsers = await fetchSignedUpUsers(performance.id);
  }

  async function selectInstrument(instrument: any) {
    const userId = get(user)?.id;
    if (!userId || !performance?.id || signingUp) return;
    signingUp = true;
    try {
      const { data, error: e } = await supabase.from('performance_user').upsert({
          performance_id: performance.id,
          user_id: userId,
          instrument_id: instrument.id
      }, { onConflict: 'performance_id,user_id,instrument_id' }).select('status');
      // The trigger can reject (e.g. invite-only) or set status to 'pending'.
      if (e) { reportError(e); return; }
      if (data?.[0]?.status === 'pending') toastInfo(`Solicitud enviada para ${instrument.name}.`);
      else toastSuccess(`Te inscribiste en ${instrument.name}.`);
      await refreshSignedUpUsers();
    } finally {
      signingUp = false;
    }
  }

  // Re-request after a decline: the row still exists as 'declined', so delete it
  // and insert fresh to run the INSERT path of the trigger (→ pending/approved).
  async function reRequest(instrumentId: string) {
    if (!currentUserId || !performance?.id) return;
    const { error: delErr } = await supabase.from('performance_user').delete()
      .eq('performance_id', performance.id).eq('user_id', currentUserId).eq('instrument_id', Number(instrumentId));
    if (delErr) { reportError(delErr); return; }
    const { data, error: e } = await supabase.from('performance_user')
      .insert({ performance_id: performance.id, user_id: currentUserId, instrument_id: Number(instrumentId) }).select('status');
    if (e) { reportError(e); return; }
    if (data?.[0]?.status === 'pending') toastInfo('Solicitud reenviada. Pendiente de aprobación.');
    else toastSuccess('¡Te inscribiste para tocar!');
    await refreshSignedUpUsers();
  }

  // Approve/reject a pending applicant (#29). RLS + the trigger enforce who may;
  // a 0-row update means the DB refused despite the UI showing the control.
  async function decideSignup(applicant: any, decision: 'approved' | 'declined') {
    const { data, error: e } = await supabase.from('performance_user')
      .update({ status: decision })
      .eq('performance_id', performance.id).eq('user_id', applicant.user_id).eq('instrument_id', applicant.instrument_id)
      .select('user_id');
    if (e) { reportError(e); return; }
    if (!data || data.length === 0) { toastError('No tienes permiso para aprobar aquí.'); return; }
    toastSuccess(decision === 'approved' ? 'Músico aprobado.' : 'Solicitud rechazada.');
    await refreshSignedUpUsers();
  }

  async function removeInstrument(userId: string, instrumentId: string) {
    const { error: e } = await supabase.from('performance_user').delete()
      .eq('performance_id', performance.id)
      .eq('user_id', userId)
      .eq('instrument_id', Number(instrumentId));
    if (e) { reportError(e); return; }
    await refreshSignedUpUsers();
  }

  function loginWithGoogle() {
    import('$lib/supabaseClient').then(({ supabase }) => {
      supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: window.location.href }
      });
    });
  }

  function handleShare() {
    const url = window.location.href;
    const title = songTitle ? `¡Inscríbete para tocar ${songTitle}!` : '¡Inscríbete para tocar una canción!';
    const text = songTitle ? `Te invito a tocar ${songTitle} en Rock Party.` : 'Te invito a tocar una canción en Rock Party.';
    if (navigator.share) {
      navigator.share({ title, text, url });
    } else {
      showShareModal = true;
    }
  }
  function closeShareModal() {
    showShareModal = false;
  }
</script>

<div class="mt-8">
  <div class="mb-4">
    <div class="flex flex-row items-center justify-between">
      <a href="/parties/{performance?.party}" class="text-cold-light flex flex-row gap-2 mx-4 m-2"><ArrowLeft/> VOLVER</a>
      <button class="ml-auto flex items-center gap-1 bg-cold-base hover:bg-cold-light text-white rounded-lg px-3 py-1 mx-4" on:click={handleShare} title="Compartir">
        <Share2 size={18} /> Compartir
      </button>
    </div>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if performance}
    <div class="bg-base-900 rounded-lg shadow mx-4 px-6 p-4">
      <h2 class="text-3xl text-yellow font-medium mb-2">{songTitle}</h2>
      <div class="mb-2">Sugerido por:
        <img src={suggestedBy?.avatarUrl && suggestedBy.avatarUrl.trim() !== '' ? suggestedBy.avatarUrl : '/images/avatar-default.svg'} alt="Foto de perfil" class="w-6 h-6 rounded-full inline-block mx-2" />
        <span class="text-cold-light">{suggestedBy?.nickname ?? performance.suggested_by}</span>
      </div>
      {#if isBand}
        <a href={`/bands/${performance.band_id}`} class="mb-2 inline-flex items-center gap-2 text-cold-light hover:text-white">
          <Users size={16} /> La toca <span class="text-yellow">{bandName}</span>
        </a>
      {/if}
      {#if performance.key}
        <div class="mb-2 text-cold-light">Tonalidad: {performance.key}</div>
      {/if}
      {#if performance.ref_link}
        <a href={performance.ref_link} target="_blank" rel="noopener" class="text-yellow underline">Ver referencia</a>
      {/if}

      <div class="mt-4 bg-base-950 rounded-lg p-3">
        <div class="text-xs text-cold-light uppercase tracking-wide mb-2">Aprender esta canción</div>
        <div class="flex flex-wrap gap-2 mb-3">
          {#if songSpotify}
            <a href={songSpotify} target="_blank" rel="noopener" class="text-sm text-white hover:text-cold-light inline-flex items-center gap-1 border border-cold-light/30 rounded-lg px-3 py-1">Escuchar en Spotify <ExternalLink size={14} /></a>
          {/if}
          {#if ugLink}
            <a href={ugLink} target="_blank" rel="noopener" class="text-sm text-white hover:text-cold-light inline-flex items-center gap-1 border border-cold-light/30 rounded-lg px-3 py-1">Acordes (Ultimate Guitar) <ExternalLink size={14} /></a>
          {/if}
        </div>
        {#if myTutorials.length}
          <!-- Only what YOU are playing, and labelled as a YouTube link rather
               than as a bare instrument name — the old version was six pills
               named exactly like the six signup options. -->
          <div class="text-xs text-cold-light mb-1">
            {myTutorials.length === 1 ? 'Tutorial para tu instrumento' : 'Tutoriales para tus instrumentos'}
          </div>
          <div class="flex flex-wrap gap-2">
            {#each myTutorials as t (t.name)}
              <a href={t.url} target="_blank" rel="noopener"
                 class="text-xs text-cold-light hover:text-white border border-cold-light/30 rounded-full px-3 py-1 inline-flex items-center gap-1">
                {t.name} en YouTube <ExternalLink size={12} />
              </a>
            {/each}
          </div>
        {/if}
      </div>

      <h3 class="text-2xl text-white font-medium mt-6 mb-2">Participantes</h3>
      <ul class="mb-4">
        {#each participants as u}
          <li class="mb-2 p-2 bg-cold-base rounded-lg flex gap-2 items-center justify-between">
            <div>
              <span class="font-semibold text-yellow">{u.nickname}</span>
              <span class="text-cold-light">— {u.instrument}</span>
              {#if u.status === 'pending'}<span class="text-yellow text-sm ml-1">· pendiente</span>{/if}
            </div>
            {#if !isBand && currentUserId && u.user_id === currentUserId}
              <button class="bg-cold-base text-white rounded-lg px-3 py-1 ml-2" on:click={() => removeInstrument(u.user_id, u.instrument_id)}>{u.status === 'pending' ? 'cancelar' : 'eliminar'} <Trash2 class="inline" size={16} /></button>
            {/if}
          </li>
        {/each}
        {#if participants.length === 0}
          <li class="text-cold-light">Nadie se ha anotado aún.</li>
        {/if}
      </ul>
      {#if !isBand && canApprove && pendingApplicants.length}
        <h3 class="text-2xl text-white font-medium mt-6 mb-2">Por aprobar</h3>
        <div class="mb-4 flex flex-col gap-3">
          {#each groupedPending as group}
            <div>
              <div class="text-xs text-cold-light uppercase tracking-wide mb-1">{group.instrument}</div>
              {#each group.applicants as applicant}
                <div class="flex items-center gap-2 py-1 border-b border-base-950 last:border-0">
                  <span class="flex-1 text-white truncate">{applicant.nickname}</span>
                  <button on:click={() => decideSignup(applicant, 'approved')} aria-label="Aprobar" class="p-1 text-green-500 hover:text-green-400"><Check size={20} /></button>
                  <button on:click={() => decideSignup(applicant, 'declined')} aria-label="Rechazar" class="p-1 text-red-500 hover:text-red-400"><X size={20} /></button>
                </div>
              {/each}
            </div>
          {/each}
        </div>
      {/if}
      {#if !isBand}
        {#each myDeclined as u}
          <div class="mb-3 p-3 bg-base-950 rounded-lg flex items-center justify-between gap-2">
            <span class="text-cold-light text-sm">Tu solicitud para <span class="text-white">{u.instrument}</span> fue rechazada.</span>
            <button class="bg-cold-base text-white rounded-lg px-3 py-1 shrink-0" on:click={() => reRequest(u.instrument_id)}>Solicitar de nuevo</button>
          </div>
        {/each}
        {#if currentUserId}
          {#if canSelfSignup}
            {#if availableInstruments.length}
              <!-- Instruments inline rather than behind a modal: the modal WAS the
                   confusion — the only instrument list on screen was the YouTube
                   one. No confirm step: undo is one tap on your own row in
                   Participantes, and a confirm in front of the primary action is
                   the opposite of streamlining it. -->
              <div class="bg-base-950 rounded-lg p-4 mb-4 flex flex-col gap-3">
                <div>
                  <div class="text-white">¿Qué vas a tocar?</div>
                  <p class="text-cold-light text-xs mt-0.5 leading-snug">
                    {autoApprove
                      ? 'Toca tu instrumento para inscribirte.'
                      : 'Toca tu instrumento para solicitar — el organizador aprueba.'}
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  {#each availableInstruments as inst (inst.id)}
                    <button type="button" on:click={() => selectInstrument(inst)} disabled={signingUp}
                            class="border border-cold-base bg-cold-base text-white rounded-lg px-4 py-2 text-sm hover:bg-cold-light hover:text-black transition disabled:opacity-50">
                      {inst.name}
                    </button>
                  {/each}
                </div>
              </div>
            {:else}
              <div class="w-full text-center text-cold-light mb-4">Todos los cupos están tomados.</div>
            {/if}
          {:else}
            <div class="w-full text-center text-cold-light mb-4">Este toque es solo por invitación.</div>
          {/if}
        {:else}
          <div class="w-full flex justify-center">
            <button class="bg-cold-base text-white rounded-lg p-2 px-4 mb-4" on:click={loginWithGoogle}>Inicia sesión para tocar</button>
          </div>
        {/if}
      {:else}
        <div class="w-full text-center text-cold-light mb-4">Esta canción la toca la banda completa.</div>
      {/if}
    </div>
  {/if}
</div>

<!-- Share Modal -->
{#if showShareModal}
  <ShareModal url={window.location.href} title={songTitle} on:close={closeShareModal} />
{/if}
