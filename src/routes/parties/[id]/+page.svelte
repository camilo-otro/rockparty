<script lang="ts">
  // Imports
  import { onMount, onDestroy, tick } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, ChevronUp, ChevronDown, Share2, Edit, MapPin, Plus } from 'lucide-svelte';
  import PerformanceListItem from '../../../lib/components/PerformanceListItem.svelte';
  import { user } from '$lib/stores/user';
  import ShareModal from '$lib/components/ShareModal.svelte';
  import StatusBadge from '$lib/components/StatusBadge.svelte';
  import type { Database, TablesUpdate } from '$lib/database.types';
  import { reportError, toastSuccess, toastError } from '$lib/stores/toasts';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';

  type PartyStatus = Database['public']['Enums']['party_status'];

  // State variables
  let party: any = null;
  let venue: any = null;
  let performances: any[] =   [];
  let songs: any[] = [];
  let users: any[] = [];
  let partyPerformers: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;
  let currentUserId: string | null = null;
  let unsubscribeUser: () => void;
  let reorderMode = false;
  let justMovedId: number | null = null;
  let showShareModal = false;
  let partyAdmins: string[] = [];
  let venueAdmins: string[] = [];
  let usersLoaded = false;
  // In-app confirm/reason dialog (native prompt()/confirm() are blocked in some
  // browser contexts — mobile/webviews — where they throw and do nothing).
  let confirmDialog: { title: string; body?: string; withReason: boolean; confirmLabel: string; run: (note: string | null) => Promise<void> | void } | null = null;
  let dialogNote = '';

  $: canAdmin = !!currentUserId && (party?.created_by === currentUserId || partyAdmins.includes(currentUserId));
  // Venue admin of THIS party's venue (its creator or a listed venue_admin).
  $: isVenueAdmin = !!currentUserId && (venue?.created_by === currentUserId || venueAdmins.includes(currentUserId));

  async function setStatus(next: PartyStatus, reason: string | null = null): Promise<boolean> {
    if (!party) return false;
    const patch: TablesUpdate<'party'> = { status: next };
    if (reason) patch.cancel_reason = reason;
    // .select() so we can tell a silent RLS denial (0 rows) from a real update.
    const { data, error: e } = await supabase.from('party').update(patch).eq('id', party.id).select('id');
    if (e) { reportError(e); return false; }
    if (!data || data.length === 0) { toastError('No tienes permiso para cambiar el estado de este toque.'); return false; }
    party = { ...party, status: next };
    return true;
  }
  async function publish() {
    // If the venue requires approval and the organizer isn't a venue admin,
    // the toque goes to the venue's queue; otherwise it's confirmed directly.
    if (venue?.requires_approval && !isVenueAdmin) {
      if (await setStatus('pending_venue')) toastSuccess('Enviado al local para aprobación.');
    } else {
      if (await setStatus('confirmed')) toastSuccess('Toque publicado.');
    }
  }
  function openDialog(d: NonNullable<typeof confirmDialog>) { confirmDialog = d; dialogNote = ''; }
  function closeDialog() { confirmDialog = null; dialogNote = ''; }
  async function runDialog() {
    const d = confirmDialog;
    const note = dialogNote.trim() || null;
    closeDialog();
    if (d) await d.run(note);
  }

  function cancelToque() {
    openDialog({
      title: '¿Cancelar este toque?',
      body: 'Dejará de ser visible para el público.',
      withReason: false,
      confirmLabel: 'Sí, cancelar',
      run: async () => {
        if (await setStatus('cancelled', 'organizer')) toastSuccess('Toque cancelado.');
      }
    });
  }
  // Venue-admin decisions on a pending_venue toque.
  async function approveToque() {
    if (!party) return;
    const { data, error: e } = await supabase.from('party').update({ status: 'confirmed', approved_by_venue: true }).eq('id', party.id).select('id');
    if (e) { reportError(e); return; }
    if (!data || data.length === 0) { toastError('No tienes permiso para aprobar este toque.'); return; }
    party = { ...party, status: 'confirmed', approved_by_venue: true };
    toastSuccess('Toque aprobado.');
  }
  function declineToque() {
    openDialog({
      title: 'Rechazar este toque',
      body: 'El organizador verá tu decisión. Su setlist se conserva.',
      withReason: true,
      confirmLabel: 'Rechazar',
      run: async (note) => {
        const { data, error: e } = await supabase.from('party')
          .update({ status: 'cancelled', cancel_reason: 'venue_declined', cancel_note: note })
          .eq('id', party.id).select('id');
        if (e) { reportError(e); return; }
        if (!data || data.length === 0) { toastError('No tienes permiso para rechazar este toque.'); return; }
        party = { ...party, status: 'cancelled', cancel_reason: 'venue_declined', cancel_note: note };
        toastSuccess('Toque rechazado.');
      }
    });
  }

  // Derived helpers
  function getSongTitle(songId: number) {
    const song = songs.find(s => s.id === songId);
    return song ? song.title : 'Sin título';
  }
  function getSongArtist(songId: number) {
    const song = songs.find(s => s.id === songId);
    return song ? song.artist : '';
  }
  function getUserNickname(userId: string) {
    const usr = users.find(u => u.id === userId);
    return usr ? usr.nickname : 'Anónimo';
  }
  function getUserAvatar(userId: string) {
    const usr = users.find(u => u.id === userId);
    return usr && usr.avatarUrl ? usr.avatarUrl : '/images/avatar-default.svg';
  }

  // Setlist reordering (#59): a dedicated mode with up/down arrows. Swapping two
  // adjacent items and re-numbering the array is deterministic — no drag, no
  // DOM↔data desync. We persist the FULL renumbered list (not just the two moved
  // rows) so any move leaves the stored order a clean 0..n — this self-heals the
  // drifted/duplicate/null orders that made the old drag flaky.
  async function moveSong(index: number, dir: -1 | 1) {
    const target = index + dir;
    if (target < 0 || target >= performances.length) return;
    const movedId = performances[index].id;
    const arr = [...performances];
    [arr[index], arr[target]] = [arr[target], arr[index]];
    arr.forEach((p, i) => (p.order = i));
    performances = arr;
    // Flash the moved row (toggle via tick so the animation restarts on repeats).
    justMovedId = null;
    await tick();
    justMovedId = movedId;
    const results = await Promise.all(
      arr.map((p) => supabase.from('performance').update({ order: p.order }).eq('id', p.id))
    );
    const err = results.find((r) => r.error)?.error;
    if (err) reportError(err);
  }

  function handleShare() {
    const url = window.location.href;
    const title = party?.title || 'te invito a esta Rock Party';
    const text = party?.description || '';
    if (navigator.share) {
      navigator.share({ title, text, url });
    } else {
      showShareModal = true;
    }
  }

  function handleEdit() {
    if (party?.id) {
      window.location.href = `/parties/${party.id}/edit`;
    }
  }

  function closeShareModal() {
    showShareModal = false;
  }

  // Lifecycle
  onMount(async () => {
    unsubscribeUser = user.subscribe(u => {
      currentUserId = u?.id ?? null;
    });
    const id = page.params.id;
    const { data, error: err } = await supabase.from('party').select('*').eq('id', Number(id)).single();
    party = data;
    // Fetch party admins
    const { data: adminData } = await supabase.from('party_admin').select('user_id').eq('party_id', Number(id));
    partyAdmins = adminData ? adminData.map(a => a.user_id) : [];
    if (err) {
      error = err.message;
    } else {
      party = data;
      if (party?.venue) {
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name, address, requires_approval, created_by').eq('id', party.venue).single();
        if (!venueErr) {
          venue = venueData;
        }
        // Load the venue's admins so we can offer approve/decline to them.
        const { data: vAdminData } = await supabase.from('venue_admin').select('user_id').eq('venue_id', party.venue);
        venueAdmins = vAdminData ? vAdminData.map(a => a.user_id) : [];
      }
      // Fetch performances for this party
      const { data: perfData, error: perfErr } = await supabase.from('performance').select('id, song, suggested_by, ref_link, key, order').eq('party', Number(id));
      if (perfErr) {
        errorPerformances = perfErr.message;
      } else {
        // Sort by stored order, unordered (null) songs last; then normalize to a
        // clean 0..n locally so display + reorder start sane even if stored orders
        // drifted (the next move persists a clean 0..n for everyone).
        const performanceList = (perfData ?? []).sort(
          (a, b) => (a.order ?? Number.MAX_SAFE_INTEGER) - (b.order ?? Number.MAX_SAFE_INTEGER)
        );
        performanceList.forEach((perf, index) => { perf.order = index; });
        performances = performanceList;
        // Fetch all songs and users referenced in performances
        const songIds = [...new Set(performances.map(p => p.song))];
        const userIds = [...new Set(performances.map(p => p.suggested_by))];
        userIds.push(party.created_by);
        const { data: songData } = await supabase.from('song').select('id, title, artist').in('id', songIds);
        
        // Fetch performers and their instruments first
        const { data: perfUsers } = await supabase.from('performance_user').select('user_id, instrument_id, performance_id').in('performance_id', performances.map(p => p.id));
        
        // Add all performer user IDs to the userIds array
        const performerUserIds = [...new Set((perfUsers ?? []).map(p => p.user_id))];
        const allUserIds = [...new Set([...userIds, ...performerUserIds])];
        
        const { data: userData } = await supabase.from('profile').select('id, nickname, avatarUrl: avatar_url').in('id', allUserIds);
        const { data: instrumentData } = await supabase.from('instrument').select('id, name');
        songs = songData ?? [];
        users = userData ?? [];
        usersLoaded = true;
      
        // Group by user and count songs
        const performerMap: Record<string, { user_id: string, instruments: string[], songCount: number }> = {};
        for (const perfUser of perfUsers ?? []) {
          if (!performerMap[perfUser.user_id]) {
            performerMap[perfUser.user_id] = { user_id: perfUser.user_id, instruments: [], songCount: 0 };
          }
          const inst = instrumentData?.find(i => i.id === perfUser.instrument_id);
          if (inst && inst.name) {
            const instName = inst.name;
            // Only add instrument if not already present
            if (!performerMap[perfUser.user_id].instruments.includes(instName)) {
              performerMap[perfUser.user_id].instruments.push(instName);
            }
          }
          performerMap[perfUser.user_id].songCount += 1;
        }
        partyPerformers = Object.values(performerMap).sort((a, b) => b.songCount - a.songCount);

        // Add performers data to each performance
        performances = performances.map(perf => {
          const perfMusicians = (perfUsers ?? []).filter(u => u.performance_id === perf.id);
          
          // Create performers array with user avatars
          const performers = perfMusicians.map(pm => ({
            instrument_id: pm.instrument_id,
            user_id: pm.user_id,
            user_avatar: getUserAvatar(pm.user_id)
          }));
          
          return { ...perf, performers };
        });
      }
      loadingPerformances = false;
    }
    loading = false;
  });

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser();
  });
</script>

<style>
  /* Reorder cue (#59): the moved row flashes a lighter grey and settles back to
     base-900. Pure background-color — no layout/transform, so it can't shift the
     list. Ends exactly at base-900 so there's no snap when the animation clears. */
  @keyframes flashMove {
    from { background-color: #3a3a3a; }
    to   { background-color: #262626; }
  }
  .flash-move {
    animation: flashMove 0.6s ease-out;
  }
</style>

<div class="mt-2 p-4 flex flex-col gap-4">
  <div class="flex flex-row w-full justify-between">
    <a href="/parties" class="text-bold text-cold-light flex flex-row"><ChevronLeft />VOLVER</a>
    {#if currentUserId == party?.created_by || partyAdmins && currentUserId && partyAdmins.includes(currentUserId)}
      <button on:click={handleEdit} class="bg-cold-light text-black rounded-lg px-4 py-2 inline-flex items-center gap-2">
        <Edit size={18} />
      </button>
    {/if}
  </div>
  {#if loading}
    <div class="text-white p-4">Cargando...</div>
  {:else if error}
    <div class="text-red-500 p-4">Error: {error}</div>
  {:else if party}
    <div class="flex flex-row justify-between items-start gap-3">
      <h2 class="text-4xl text-yellow font-medium">{party.title}</h2>
      <StatusBadge status={party.status} />
    </div>
    {#if canAdmin && party.status === 'draft'}
      <div class="bg-base-900 rounded-lg p-4 flex flex-col gap-3">
        <p class="text-cold-light text-sm leading-snug">
          Este toque es un <span class="text-white">borrador</span> — solo tú y sus administradores lo ven.
          {#if venue?.requires_approval && !isVenueAdmin}
            Al publicar, el local deberá aprobarlo antes de que sea visible.
          {/if}
        </p>
        <div class="flex items-center gap-3">
          <button on:click={publish} class="flex-1 bg-cold-base hover:bg-cold-light hover:text-black text-white rounded-lg px-6 py-2 transition">Publicar toque</button>
          <button on:click={cancelToque} class="text-red-400 hover:text-red-300 text-sm px-2 py-2 transition">Descartar</button>
        </div>
      </div>
    {:else if party.status === 'pending_venue' && isVenueAdmin}
      <div class="bg-base-900 rounded-lg p-4 flex flex-col gap-3">
        <p class="text-cold-light text-sm leading-snug">
          Este toque está <span class="text-white">pendiente de tu aprobación</span> como administrador del local.
        </p>
        <div class="flex items-center gap-3">
          <button on:click={approveToque} class="flex-1 bg-cold-base hover:bg-cold-light hover:text-black text-white rounded-lg px-6 py-2 transition">Aprobar</button>
          <button on:click={declineToque} class="text-red-400 hover:text-red-300 text-sm px-2 py-2 transition">Rechazar</button>
        </div>
      </div>
    {:else if party.status === 'pending_venue' && canAdmin}
      <div class="bg-base-900 rounded-lg p-4 flex flex-col gap-3">
        <p class="text-cold-light text-sm leading-snug">
          Esperando la <span class="text-white">aprobación del local</span>. Te avisaremos cuando decidan.
        </p>
        <div class="flex justify-end">
          <button on:click={cancelToque} class="text-red-400 hover:text-red-300 text-sm px-2 py-2 transition">Cancelar toque</button>
        </div>
      </div>
    {:else if canAdmin && party.status !== 'completed' && party.status !== 'cancelled'}
      <div class="flex justify-end">
        <button on:click={cancelToque} class="text-red-400 hover:text-red-300 text-sm border border-red-400/40 hover:border-red-300 rounded-lg px-3 py-1 transition">Cancelar toque</button>
      </div>
    {/if}
    {#if party.status === 'cancelled' && party.cancel_reason === 'venue_declined'}
      <div class="bg-base-900 rounded-lg p-4 flex flex-col gap-2">
        <p class="text-white">Este toque fue <span class="text-red-400">rechazado por el local</span>.</p>
        {#if party.cancel_note}<p class="text-cold-light text-sm">Motivo: {party.cancel_note}</p>{/if}
        <p class="text-cold-light text-sm">El setlist se conserva más abajo. Puedes <a href={`/venues/${party.venue}`} class="text-cold-light underline">contactar al local</a> o crear un nuevo toque.</p>
      </div>
    {/if}
    <div class="">Organizado por: {#if usersLoaded}<img src={getUserAvatar(party.created_by)} alt="User Avatar" class="w-5 h-5 border-yellow rounded-full inline-block mx-2" /><span class="text-cold-light">{getUserNickname(party.created_by)}</span>{/if}</div>
    <div class="text-lg mb-2 text-white">{party.description}</div>
    <div class="mb-2 text-white">{dayjs(party.date).locale('es').format('ddd D [de] MMMM, YYYY')}</div>
    <div class="mb-2 text-cold-light"><MapPin class="inline-block" size={18} /> {venue ? venue.name : 'Cargando...'} - {venue ? venue.address : ''}</div>
    <div class="mt-2 w-full flex items-center">
      <button on:click={handleShare} class="bg-cold-base text-white rounded-lg p-2 px-6 inline-flex items-center gap-2 m-auto">
        Compartir
        <Share2 class="w-5 h-5" />
      </button>
    </div>
    <div class="flex items-center justify-between mt-4 mb-2">
      <h3 class="text-3xl text-white font-medium tracking-widest">SETLIST</h3>
      {#if canAdmin && performances.length > 1}
        <button on:click={() => reorderMode = !reorderMode} class="text-cold-light text-sm border border-cold-light/40 hover:border-cold-light rounded-lg px-3 py-1 transition">
          {reorderMode ? 'Listo' : 'Reordenar'}
        </button>
      {/if}
    </div>
    <div class="bg-base-950 rounded-lg overflow-hidden">
      {#if loadingPerformances}
        <div class="text-white">Cargando Setlist...</div>
      {:else if errorPerformances}
        <div class="text-red-500">Error: {errorPerformances}</div>
      {:else if performances.length === 0}
        <div class="text-white">No hay canciones en el Setlist.</div>
      {:else}
        <ul class="grid grid-cols-1 space-y-[1px]">
          {#each performances as perf, index (perf.id)}
            <li class="bg-base-900 px-4 p-3" class:flash-move={justMovedId === perf.id}>
              {#if reorderMode}
                <div class="flex items-center gap-2">
                  <span class="text-gray-400 text-2xl font-medium mr-2 w-7 text-center shrink-0">{index + 1}</span>
                  <div class="flex-1 min-w-0">
                    <div class="text-lg text-yellow truncate">{getSongTitle(perf.song)}</div>
                    <div class="text-sm text-cold-light truncate">{getSongArtist(perf.song)}</div>
                  </div>
                  <div class="flex flex-col shrink-0">
                    <button on:click={() => moveSong(index, -1)} disabled={index === 0} aria-label="Subir" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronUp size={22} /></button>
                    <button on:click={() => moveSong(index, 1)} disabled={index === performances.length - 1} aria-label="Bajar" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronDown size={22} /></button>
                  </div>
                </div>
              {:else}
                <a href={`/performance/${perf.id}`} class="block">
                  <div class="flex items-center gap-2">
                    <span class="text-gray-400 text-3xl font-medium mr-2">{index + 1}</span>
                    <div class="flex-1">
                      <PerformanceListItem
                        title={getSongTitle(perf.song)}
                        artist={getSongArtist(perf.song)}
                        key={perf.key}
                        performers={perf.performers || []}
                      />
                    </div>
                  </div>
                </a>
              {/if}
            </li>
          {/each}
        </ul>
      {/if}
      {#if !reorderMode}
        <a href={`/performance/create?partyId=${party.id}`} class="w-full bg-cold-base text-white p-3 inline-block text-center">Sugerir una canción <Plus class="inline-block" /></a>
      {/if}
    </div>
    <h3 class="text-3xl text-white font-medium pt-4 mt-2">MÚSICOS</h3>
    <div class="bg-base-950 rounded-lg overflow-hidden mt-2">
      <ul class="space-y-[1px]">
        {#each partyPerformers as performer}
          <li class="flex flex-col bg-base-900 gap-2 p-4">
            <div class="flex flex-row gap-2">
                <img src={getUserAvatar(performer.user_id)} alt="Avatar" class="w-6 h-6 rounded-full" />
                <span class="text-cold-light font-semibold">{getUserNickname(performer.user_id)}</span>
            </div>
            <div class="flex flex-row justify-between">
              <span class="text-sm text-white">{performer.instruments.join(', ')}</span>
              <span class="text-sm text-cold-light font-bold ml-2">{performer.songCount} CANCIÓN{performer.songCount === 1 ? '' : 'ES'}</span>
            </div>
          </li>
        {/each}
        {#if partyPerformers.length === 0}
          <li class="text-cold-light">Nadie se ha anotado aún.</li>
        {/if}
      </ul>
    </div>
    <div class="flex flex-row justify-between mb-4">
      <div class="mt-2 w-full flex items-center">
        <button on:click={handleShare} class="bg-cold-base text-white rounded-lg p-2 px-6 inline-flex items-center gap-2 m-auto">
          Compartir
          <Share2 class="w-5 h-5" />
        </button>
      </div>
    </div>
    {#if showShareModal}
      <ShareModal url={window.location.href} title={party?.title} on:close={closeShareModal} />
    {/if}
    {#if confirmDialog}
      <div class="fixed inset-0 bg-black/60 z-50 flex items-center justify-center p-4" on:click={closeDialog}>
        <div class="bg-base-900 rounded-lg p-6 max-w-md w-full flex flex-col gap-3" on:click|stopPropagation>
          <h3 class="text-xl text-white">{confirmDialog.title}</h3>
          {#if confirmDialog.body}<p class="text-cold-light text-sm">{confirmDialog.body}</p>{/if}
          {#if confirmDialog.withReason}
            <textarea bind:value={dialogNote} rows="2" maxlength="300" placeholder="Motivo (opcional)" class="p-2 border rounded-lg w-full resize-none"></textarea>
          {/if}
          <div class="flex justify-end gap-3 mt-1">
            <button on:click={closeDialog} class="text-cold-light px-3 py-2">Volver</button>
            <button on:click={runDialog} class="bg-cold-base text-white rounded-lg px-4 py-2">{confirmDialog.confirmLabel}</button>
          </div>
        </div>
      </div>
    {/if}
    <div class="flex flex-row items-center">
      <a href="/parties" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft />VOLVER</a>
    </div>
  {/if}
</div>
