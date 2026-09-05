<script lang="ts">
  // Imports
  import { onMount, onDestroy, tick } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, ChevronUp, ChevronDown, Check, X, Share2, Edit, MapPin, Plus, Trash2, AlertTriangle, Copy, Users } from 'lucide-svelte';
  import PerformanceListItem from '../../../lib/components/PerformanceListItem.svelte';
  import { user } from '$lib/stores/user';
  import ShareModal from '$lib/components/ShareModal.svelte';
  import StatusBadge from '$lib/components/StatusBadge.svelte';
  import type { Database, TablesUpdate } from '$lib/database.types';
  import { reportError, toastSuccess, toastError } from '$lib/stores/toasts';
  import { normalizeText } from '$lib/sanitize';
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
  let setlistView: 'orden' | 'faltan' | 'para-ti' = 'orden'; // ephemeral view (#60)
  let justMovedId: number | null = null;
  let instrumentsById: Record<number, string> = {};
  let expandedApprovals = new Set<number>();
  let myInstrumentIds: number[] = []; // instruments the viewer plays (#32)
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

  // Gaps to fill (#32): a slot is open when no APPROVED player holds it. The
  // alert counts songs with any gap, and — for a logged-in musician — how many
  // have a gap in an instrument THEY play (the actionable number).
  $: allInstrumentIds = Object.keys(instrumentsById).map(Number);
  function openInstrumentIds(perf: any): number[] {
    // Band-owned songs (#74) aren't open jams — they have no instrument gaps.
    if (perf.band) return [];
    return allInstrumentIds.filter((id) => !(perf.performers ?? []).some((p: any) => p.instrument_id === id));
  }
  $: songsWithGaps = allInstrumentIds.length ? performances.filter((p) => openInstrumentIds(p).length > 0).length : 0;
  $: songsForMe = myInstrumentIds.length ? performances.filter((p) => openInstrumentIds(p).some((id) => myInstrumentIds.includes(id))).length : 0;

  // Context-sort views (#60) — a non-destructive re-presentation of the setlist;
  // the stored `order` (running order) is never touched. Reorder always uses the
  // canonical order.
  $: displayed = reorderMode
    ? performances
    : setlistView === 'faltan'
      ? [...performances].sort((a, b) => openInstrumentIds(b).length - openInstrumentIds(a).length)
      : setlistView === 'para-ti'
        ? performances.filter((p) => openInstrumentIds(p).some((id) => myInstrumentIds.includes(id)))
        : performances;

  // Band sets: a band's CONSECUTIVE songs render as one block with the lineup
  // shown once, instead of repeating it on every row. Only in the running-order
  // view — the other views re-sort/filter, so "consecutive" would be arbitrary —
  // and never while reordering, where rows must stay individually movable.
  // When grouping is off, everything is one open run => the original flat list.
  $: grouping = !reorderMode && setlistView === 'orden';
  $: runs = grouping
    ? displayed.reduce<{ band: any; items: any[] }[]>((acc, p) => {
        const last = acc[acc.length - 1];
        const sameRun = last && (last.band && p.band ? last.band.id === p.band.id : !last.band && !p.band);
        if (sameRun) last.items.push(p);
        else acc.push({ band: p.band, items: [p] });
        return acc;
      }, [])
    : [{ band: null, items: displayed }];

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
        const cleanNote = normalizeText(note, 500) || null;
        const { data, error: e } = await supabase.from('party')
          .update({ status: 'cancelled', cancel_reason: 'venue_declined', cancel_note: cleanNote })
          .eq('id', party.id).select('id');
        if (e) { reportError(e); return; }
        if (!data || data.length === 0) { toastError('No tienes permiso para rechazar este toque.'); return; }
        party = { ...party, status: 'cancelled', cancel_reason: 'venue_declined', cancel_note: cleanNote };
        toastSuccess('Toque rechazado.');
      }
    });
  }
  // A venue owner/admin cancelling a CONFIRMED/LIVE toque at their venue (#53).
  // Distinct reason from an organizer cancel or a pre-approval decline.
  function venueCancelToque() {
    openDialog({
      title: 'Cancelar este toque en tu local',
      body: 'El toque se cancelará y el organizador verá tu decisión. Su setlist se conserva.',
      withReason: true,
      confirmLabel: 'Cancelar toque',
      run: async (note) => {
        const cleanNote = normalizeText(note, 500) || null;
        const { data, error: e } = await supabase.from('party')
          .update({ status: 'cancelled', cancel_reason: 'venue_cancelled', cancel_note: cleanNote })
          .eq('id', party.id).select('id');
        if (e) { reportError(e); return; }
        if (!data || data.length === 0) { toastError('No tienes permiso para cancelar este toque.'); return; }
        party = { ...party, status: 'cancelled', cancel_reason: 'venue_cancelled', cancel_note: cleanNote };
        toastSuccess('Toque cancelado.');
      }
    });
  }

  // Clone a terminal (cancelled/completed) toque into a fresh draft the current
  // user owns, copying the setlist + its approved lineup so re-proposing doesn't
  // mean rebuilding by hand (#52). Keeps the old venue/date as a starting point;
  // the organizer adjusts them before publishing.
  let cloning = false;
  async function cloneToque() {
    if (!party || !currentUserId || cloning) return;
    cloning = true;
    try {
      const { data: np, error: pe } = await supabase.from('party').insert({
        title: `${party.title ?? 'Toque'} (copia)`,
        description: party.description,
        date: party.date,
        venue: party.venue,
        created_by: currentUserId,
        performer_approval: party.performer_approval,
        status: 'draft'
      }).select('id').single();
      if (pe || !np) { reportError(pe ?? new Error('No se pudo crear el borrador.')); return; }
      const newId = np.id;
      // Copy the setlist (performances).
      if (performances.length) {
        const rows = performances.map((p: any) => ({
          party: newId, song: p.song, key: p.key, ref_link: p.ref_link,
          order: p.order, suggested_by: p.suggested_by ?? currentUserId
        }));
        const { data: newPerfs, error: perfErr } = await supabase.from('performance').insert(rows).select();
        if (perfErr) reportError(perfErr);
        else if (newPerfs) {
          // Map new performances to their source by order (unique per party), then
          // copy each song's approved lineup. The status trigger re-approves them
          // (the cloner is the new draft's admin).
          const byOrder: Record<number, number> = {};
          for (const p of newPerfs) if (p.order != null) byOrder[p.order] = p.id;
          const signupRows: any[] = [];
          for (const p of performances) {
            const newPid = p.order != null ? byOrder[p.order] : undefined;
            if (!newPid) continue;
            for (const perf of (p.performers ?? [])) {
              signupRows.push({ performance_id: newPid, user_id: perf.user_id, instrument_id: perf.instrument_id });
            }
          }
          if (signupRows.length) {
            const { error: suErr } = await supabase.from('performance_user').insert(signupRows);
            if (suErr) reportError(suErr);
          }
        }
      }
      toastSuccess('Borrador creado a partir de este toque.');
      // Full navigation (not goto): the destination is the SAME route with a new
      // id, so the component wouldn't remount and its onMount data load wouldn't
      // re-run — leaving the old toque's data on screen.
      window.location.href = `/parties/${newId}`;
    } finally {
      cloning = false;
    }
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

  // Estimated set length: song durations (song.duration is decimal MINUTES) plus
  // a minute of transition between songs. Approximate by design — a handful of
  // catalog songs still sit at the default duration.
  const TRANSITION_MIN = 1;
  function setMinutes(items: any[]): number {
    const songMins = items.reduce((t, p) => t + (songs.find((s) => s.id === p.song)?.duration ?? 0), 0);
    return songMins + Math.max(0, items.length - 1) * TRANSITION_MIN;
  }
  function formatMinutes(mins: number): string {
    const m = Math.round(mins);
    if (m < 60) return `${m} min`;
    const h = Math.floor(m / 60);
    const rest = m % 60;
    return rest ? `${h} h ${rest} min` : `${h} h`;
  }

  // Band sets collapse to a summary; expand on tap. A set with something the
  // viewer can approve stays open so the action isn't hidden.
  let expandedSets = new Set<number>();
  function toggleSet(key: number) {
    if (expandedSets.has(key)) expandedSets.delete(key);
    else expandedSets.add(key);
    expandedSets = new Set(expandedSets);
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
    // Flash the moved row. Remove the class, force a reflow on that row, then
    // re-add — the reliable way to restart a CSS animation regardless of whether
    // the keyed list moved this node up or down (a plain toggle can get coalesced).
    justMovedId = null;
    await tick();
    const el = document.querySelector(`[data-perf-id="${movedId}"]`) as HTMLElement | null;
    if (el) void el.offsetWidth;
    justMovedId = movedId;
    const results = await Promise.all(
      arr.map((p) => supabase.from('performance').update({ order: p.order }).eq('id', p.id))
    );
    const err = results.find((r) => r.error)?.error;
    if (err) reportError(err);
  }

  // Remove a song from the setlist (#62). Party admins only (RLS enforces it);
  // the DELETE cascades to this song's signups. Confirm first, and treat a
  // 0-row delete as an RLS denial rather than silent success.
  function removeSong(perf: any) {
    openDialog({
      title: '¿Quitar esta canción del setlist?',
      body: `Se eliminará "${getSongTitle(perf.song)}" y las inscripciones a esta canción.`,
      withReason: false,
      confirmLabel: 'Quitar',
      run: async () => {
        const { data, error: e } = await supabase.from('performance').delete().eq('id', perf.id).select('id');
        if (e) { reportError(e); return; }
        if (!data || data.length === 0) { toastError('No tienes permiso para quitar esta canción.'); return; }
        performances = performances.filter((p) => p.id !== perf.id);
        toastSuccess('Canción eliminada del setlist.');
      }
    });
  }

  // Per-song approval (#29). An approver is a party admin, or — in proponent
  // mode — the song's proponent.
  function canApproveSong(perf: any): boolean {
    return canAdmin || (party?.performer_approval === 'proponent' && !!currentUserId && perf?.suggested_by === currentUserId);
  }
  function toggleApprovals(perfId: number) {
    if (expandedApprovals.has(perfId)) expandedApprovals.delete(perfId);
    else expandedApprovals.add(perfId);
    expandedApprovals = new Set(expandedApprovals);
  }
  function pendingByInstrument(pending: any[]): { instrument_id: number; applicants: any[] }[] {
    const map: Record<number, any[]> = {};
    for (const a of pending) (map[a.instrument_id] ??= []).push(a);
    return Object.entries(map).map(([id, applicants]) => ({ instrument_id: Number(id), applicants }));
  }
  async function decideSignup(perf: any, applicant: any, decision: 'approved' | 'declined') {
    const { data, error: e } = await supabase.from('performance_user')
      .update({ status: decision })
      .eq('performance_id', perf.id).eq('user_id', applicant.user_id).eq('instrument_id', applicant.instrument_id)
      .select('user_id');
    if (e) { reportError(e); return; }
    if (!data || data.length === 0) { toastError('No tienes permiso para aprobar aquí.'); return; }
    // Rebuild the affected performance as a NEW object so the keyed {#each}
    // re-pushes `performers` into PerformanceListItem (mutating in place doesn't).
    performances = performances.map((p: any) => {
      if (p.id !== perf.id) return p;
      const pending = p.pending.filter((x: any) => !(x.user_id === applicant.user_id && x.instrument_id === applicant.instrument_id));
      const performers = decision === 'approved'
        ? [...p.performers, { instrument_id: applicant.instrument_id, user_id: applicant.user_id, user_avatar: getUserAvatar(applicant.user_id) }]
        : p.performers;
      return { ...p, pending, performers };
    });
    toastSuccess(decision === 'approved' ? 'Músico aprobado.' : 'Solicitud rechazada.');
  }

  // Approve/decline a band as a UNIT (#74) — one action for the whole act.
  async function decideBandSignup(perf: any, decision: 'approved' | 'declined') {
    const { error: e } = await supabase.rpc('set_band_signup_status', { p_performance: perf.id, p_band: perf.band.id, p_status: decision });
    if (e) { reportError(e); return; }
    toastSuccess(decision === 'approved' ? 'Banda aprobada.' : 'Banda rechazada.');
    await loadSetlist(Number(page.params.id));
  }

  // Share the clean public flyer (#39), not the app detail page.
  $: flyerUrl = party?.id ? `${typeof window !== 'undefined' ? window.location.origin : ''}/flyer/${party.id}` : '';
  function handleShare() {
    const url = flyerUrl;
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
      goto(`/parties/${party.id}/edit`);
    }
  }

  // RSVP / attendance (#58). A row = "going"; count is public.
  let rsvpCount = 0;
  let iAmGoing = false;
  let rsvpBusy = false;
  async function loadRsvp() {
    if (!party?.id) return;
    const { count } = await supabase.from('party_rsvp').select('user_id', { count: 'exact', head: true }).eq('party_id', party.id);
    rsvpCount = count ?? 0;
    if (currentUserId) {
      const { data } = await supabase.from('party_rsvp').select('user_id').eq('party_id', party.id).eq('user_id', currentUserId).maybeSingle();
      iAmGoing = !!data;
    }
  }
  async function toggleRsvp() {
    if (!currentUserId || !party?.id || rsvpBusy) return;
    rsvpBusy = true;
    try {
      if (iAmGoing) {
        const { error: e } = await supabase.from('party_rsvp').delete().eq('party_id', party.id).eq('user_id', currentUserId);
        if (e) { reportError(e); return; }
        iAmGoing = false; rsvpCount = Math.max(0, rsvpCount - 1);
      } else {
        const { error: e } = await supabase.from('party_rsvp').insert({ party_id: party.id, user_id: currentUserId });
        if (e) { reportError(e); return; }
        iAmGoing = true; rsvpCount += 1;
      }
    } finally {
      rsvpBusy = false;
    }
  }

  function closeShareModal() {
    showShareModal = false;
  }

  // Load / reload just the setlist (songs + signups). Extracted so Realtime (#63)
  // can refresh it live without re-fetching the whole party. Never touches
  // reorderMode / expandedApprovals, so an in-progress interaction isn't clobbered.
  let perfIdSet = new Set<number>(); // this party's performance ids, for filtering
  async function loadSetlist(pid: number) {
    const { data: perfData, error: perfErr } = await supabase.from('performance').select('id, song, suggested_by, ref_link, key, order, band_id').eq('party', pid);
    if (perfErr) { errorPerformances = perfErr.message; return; }
    const perfs = (perfData ?? []).sort((a, b) => (a.order ?? Number.MAX_SAFE_INTEGER) - (b.order ?? Number.MAX_SAFE_INTEGER));
    perfs.forEach((perf, index) => { perf.order = index; });
    const songIds = [...new Set(perfs.map((p) => p.song).filter((x): x is number => x != null))];
    const userIds = [...new Set(perfs.map((p) => p.suggested_by).filter((x): x is string => x != null))];
    if (party?.created_by) userIds.push(party.created_by);
    const { data: songData } = songIds.length ? await supabase.from('song').select('id, title, artist, duration').in('id', songIds) : { data: [] as any[] };
    const { data: perfUsers } = perfs.length ? await supabase.from('performance_user').select('user_id, instrument_id, performance_id, status, band_id').in('performance_id', perfs.map((p) => p.id)) : { data: [] as any[] };
    // Band-owned songs (#74): resolve band names for the setlist rows.
    const bandIds = [...new Set(perfs.map((p) => p.band_id).filter((x): x is number => x != null))];
    const { data: bandData } = bandIds.length ? await supabase.from('band').select('id, name, avatar_url').in('id', bandIds) : { data: [] as any[] };
    const bandsById: Record<number, any> = Object.fromEntries((bandData ?? []).map((b: any) => [b.id, b]));
    const performerUserIds = [...new Set((perfUsers ?? []).map((p) => p.user_id))];
    const allUserIds = [...new Set([...userIds, ...performerUserIds])];
    const { data: userData } = allUserIds.length ? await supabase.from('profile').select('id, nickname, avatarUrl: avatar_url').in('id', allUserIds) : { data: [] as any[] };
    const { data: instrumentData } = await supabase.from('instrument').select('id, name');
    instrumentsById = Object.fromEntries((instrumentData ?? []).map((i: any) => [i.id, i.name]));
    songs = songData ?? [];
    users = userData ?? [];
    usersLoaded = true;

    // "MÚSICOS" lineup counts only APPROVED signups.
    const performerMap: Record<string, { user_id: string, instruments: string[], songCount: number }> = {};
    for (const perfUser of perfUsers ?? []) {
      if (perfUser.status !== 'approved') continue;
      if (!performerMap[perfUser.user_id]) performerMap[perfUser.user_id] = { user_id: perfUser.user_id, instruments: [], songCount: 0 };
      const instName = instrumentsById[perfUser.instrument_id];
      if (instName && !performerMap[perfUser.user_id].instruments.includes(instName)) performerMap[perfUser.user_id].instruments.push(instName);
      performerMap[perfUser.user_id].songCount += 1;
    }
    partyPerformers = Object.values(performerMap).sort((a, b) => b.songCount - a.songCount);

    performances = perfs.map((perf) => {
      const rows = (perfUsers ?? []).filter((u) => u.performance_id === perf.id);
      const performers = rows.filter((r) => r.status === 'approved').map((pm) => ({ instrument_id: pm.instrument_id, user_id: pm.user_id, user_avatar: getUserAvatar(pm.user_id) }));
      const pending = rows.filter((r) => r.status === 'pending').map((pm) => ({ instrument_id: pm.instrument_id, user_id: pm.user_id }));
      // Band-owned song (#74): render the band + its lineup (unique members),
      // never open-slot gaps. Approved lineup once approved, else the pending
      // proposal. All rows declined => the act was rejected (hidden below).
      let band: any = null;
      let bandLineup: any[] = [];
      if (perf.band_id) {
        const approvedRows = rows.filter((r) => r.status === 'approved');
        const pendingRows = rows.filter((r) => r.status === 'pending');
        const src = approvedRows.length ? approvedRows : pendingRows;
        const seen = new Set<string>();
        bandLineup = src.filter((r) => (seen.has(r.user_id) ? false : (seen.add(r.user_id), true)))
                        .map((r) => ({ user_id: r.user_id, user_avatar: getUserAvatar(r.user_id) }));
        band = {
          id: perf.band_id,
          name: bandsById[perf.band_id]?.name ?? 'Banda',
          avatar_url: bandsById[perf.band_id]?.avatar_url ?? null,
          pending: pendingRows.length > 0 && approvedRows.length === 0,
          declined: approvedRows.length === 0 && pendingRows.length === 0
        };
      }
      return { ...perf, performers, pending, band, bandLineup };
    })
    // Hide a fully-declined band-owned song (band-or-nothing, #74).
    .filter((p) => !(p.band && p.band.declined));
    perfIdSet = new Set(performances.map((p) => p.id));
  }

  // Live setlist (#63): another user's signup/approval/song-change refreshes the
  // list. Defer while the viewer is mid-reorder or has a dialog open, then flush.
  let setlistChannel: any = null;
  let pendingReload = false;
  function scheduleReload() {
    if (reorderMode || confirmDialog) { pendingReload = true; return; }
    loadSetlist(Number(page.params.id));
  }
  $: if (pendingReload && !reorderMode && !confirmDialog) { pendingReload = false; loadSetlist(Number(page.params.id)); }
  function subscribeSetlist(pid: number) {
    setlistChannel = supabase
      .channel(`setlist-${pid}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'performance', filter: `party=eq.${pid}` }, () => scheduleReload())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'performance_user' }, (payload: any) => {
        const rid = payload.new?.performance_id ?? payload.old?.performance_id;
        if (rid && perfIdSet.has(rid)) scheduleReload();
      })
      .subscribe();
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
      // Load the setlist (extracted into loadSetlist so Realtime can reload it).
      await loadSetlist(Number(id));
      loadingPerformances = false;
      subscribeSetlist(Number(id));
    }
    // The viewer's own instruments (#32) — powers the personalized gap alert +
    // the "you could play here" highlight on open slots.
    if (currentUserId) {
      const { data: pi } = await supabase.from('profile_instrument').select('instrument_id').eq('profile_id', currentUserId);
      myInstrumentIds = (pi ?? []).map((r: any) => r.instrument_id);
    }
    await loadRsvp();
    loading = false;
  });

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser();
    if (setlistChannel) supabase.removeChannel(setlistChannel);
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
      <div class="flex flex-col gap-1">
        <h2 class="text-4xl text-yellow font-medium">{party.title}</h2>
        {#if party.is_test}<span class="self-start text-[0.65rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-warm-base text-warm-base">Datos de prueba</span>{/if}
      </div>
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
    {:else if isVenueAdmin && (party.status === 'confirmed' || party.status === 'live')}
      <div class="bg-base-900 rounded-lg p-4 flex flex-col gap-3">
        <p class="text-cold-light text-sm leading-snug">
          Este toque está <span class="text-white">confirmado en tu local</span>. Como administrador del local puedes cancelarlo si es necesario.
        </p>
        <div class="flex justify-end">
          <button on:click={venueCancelToque} class="text-red-400 hover:text-red-300 text-sm border border-red-400/40 hover:border-red-300 rounded-lg px-3 py-1 transition">Cancelar toque en el local</button>
        </div>
      </div>
    {:else if canAdmin && (party.status === 'cancelled' || party.status === 'completed')}
      <div class="flex justify-end">
        <button on:click={cloneToque} disabled={cloning} class="text-cold-light hover:text-white text-sm border border-cold-light/40 hover:border-cold-light rounded-lg px-3 py-1 transition disabled:opacity-50 inline-flex items-center gap-2">
          <Copy size={16} /> {cloning ? 'Clonando…' : 'Clonar en un nuevo borrador'}
        </button>
      </div>
    {/if}
    {#if party.status === 'cancelled' && (party.cancel_reason === 'venue_declined' || party.cancel_reason === 'venue_cancelled')}
      <div class="bg-base-900 rounded-lg p-4 flex flex-col gap-2">
        <p class="text-white">Este toque fue <span class="text-red-400">{party.cancel_reason === 'venue_declined' ? 'rechazado' : 'cancelado'} por el local</span>.</p>
        {#if party.cancel_note}<p class="text-cold-light text-sm">Motivo: {party.cancel_note}</p>{/if}
        <p class="text-cold-light text-sm">El setlist se conserva más abajo. Puedes <a href={`/venues/${party.venue}`} class="text-cold-light underline">contactar al local</a> o crear un nuevo toque.</p>
      </div>
    {/if}
    <div class="">Organizado por: {#if usersLoaded}<img src={getUserAvatar(party.created_by)} alt="User Avatar" class="w-5 h-5 border-yellow rounded-full inline-block mx-2" /><span class="text-cold-light">{getUserNickname(party.created_by)}</span>{/if}</div>
    <div class="text-lg mb-2 text-white">{party.description}</div>
    <div class="mb-2 text-white">{dayjs(party.date).locale('es').format('ddd D [de] MMMM, YYYY')}</div>
    <div class="mb-2 text-cold-light"><MapPin class="inline-block" size={18} /> {venue ? venue.name : 'Cargando...'} - {venue ? venue.address : ''}</div>
    {#if party.status === 'confirmed' || party.status === 'live'}
      <div class="flex items-center gap-3 mt-2 mb-1">
        {#if currentUserId}
          <button on:click={toggleRsvp} disabled={rsvpBusy}
            class="rounded-lg px-4 py-2 text-sm font-medium transition disabled:opacity-50 inline-flex items-center gap-2 {iAmGoing ? 'bg-cold-base text-white' : 'border border-cold-light/50 text-cold-light hover:border-cold-light'}">
            {#if iAmGoing}<Check size={18} /> Vas a asistir{:else}Voy{/if}
          </button>
        {/if}
        <span class="text-cold-light text-sm">{rsvpCount} {rsvpCount === 1 ? 'asistente' : 'asistentes'}</span>
      </div>
    {/if}
    <div class="mt-2 w-full flex items-center">
      <button on:click={handleShare} class="bg-cold-base text-white rounded-lg p-2 px-6 inline-flex items-center gap-2 m-auto">
        Compartir
        <Share2 class="w-5 h-5" />
      </button>
    </div>
    <div class="flex items-center justify-between mt-4 mb-2">
      <h3 class="text-3xl text-white font-medium tracking-widest">SETLIST</h3>
      {#if canAdmin && performances.length > 1}
        <button on:click={() => { reorderMode = !reorderMode; if (reorderMode) setlistView = 'orden'; }} class="text-cold-light text-sm border border-cold-light/40 hover:border-cold-light rounded-lg px-3 py-1 transition">
          {reorderMode ? 'Listo' : 'Reordenar'}
        </button>
      {/if}
    </div>
    {#if !reorderMode && !loadingPerformances && performances.length > 1}
      <div class="flex flex-wrap gap-2 mb-2">
        <button on:click={() => setlistView = 'orden'} class="text-xs rounded-full px-3 py-1 transition {setlistView === 'orden' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">Orden</button>
        <button on:click={() => setlistView = 'faltan'} class="text-xs rounded-full px-3 py-1 transition {setlistView === 'faltan' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">Faltan primero</button>
        {#if myInstrumentIds.length}
          <button on:click={() => setlistView = 'para-ti'} class="text-xs rounded-full px-3 py-1 transition {setlistView === 'para-ti' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">Para ti</button>
        {/if}
      </div>
    {/if}
    {#if !reorderMode && !loadingPerformances && songsWithGaps > 0}
      <div class="flex items-center gap-3 bg-base-900 rounded-lg px-4 py-3 mb-2">
        <AlertTriangle class="text-yellow shrink-0" size={20} />
        <span class="text-white text-sm">
          {#if songsForMe > 0}
            {songsForMe === 1 ? '1 canción te necesita' : `${songsForMe} canciones te necesitan`}
          {:else}
            {songsWithGaps === 1 ? '1 canción busca músicos' : `${songsWithGaps} canciones buscan músicos`}
          {/if}
        </span>
      </div>
    {/if}
    <div class="bg-base-950 rounded-lg overflow-hidden">
      {#if loadingPerformances}
        <div class="text-white">Cargando Setlist...</div>
      {:else if errorPerformances}
        <div class="text-red-500">Error: {errorPerformances}</div>
      {:else if performances.length === 0}
        <div class="text-white">No hay canciones en el Setlist.</div>
      {:else}
      <div class="flex flex-col gap-2">
        {#if displayed.length === 0}
          <div class="bg-base-900 rounded-lg px-4 py-3 text-cold-light text-sm">Ninguna canción tiene un cupo en lo que tocas.</div>
        {/if}
        {#each runs as run}
        {#if run.band}
          <!-- Band set (#74): lineup shown once; collapses to a summary. -->
          {@const setKey = run.items[0].id}
          {@const needsAction = run.items.some((p) => p.band?.pending && canApproveSong(p))}
          {@const isOpen = expandedSets.has(setKey) || needsAction}
          <div class="rounded-lg overflow-clip border-l-2 border-cold-base">
            <button type="button" on:click={() => toggleSet(setKey)} class="w-full bg-base-900 px-4 py-2.5 flex items-center gap-3 text-left hover:bg-base-950 transition">
              {#if run.band.avatar_url}
                <img src={run.band.avatar_url} alt="" class="w-9 h-9 rounded-full object-cover border border-cold-base shrink-0" />
              {:else}
                <span class="w-9 h-9 rounded-full bg-base-950 border border-cold-base flex items-center justify-center shrink-0"><Users size={16} class="text-cold-light" /></span>
              {/if}
              <div class="flex-1 min-w-0">
                <span class="text-white truncate block">{run.band.name}</span>
                <span class="text-cold-light text-xs uppercase tracking-wide">
                  {run.items.length} {run.items.length === 1 ? 'canción' : 'canciones'} · ~{formatMinutes(setMinutes(run.items))}{#if run.band.pending} · <span class="text-yellow">pendiente</span>{/if}
                </span>
              </div>
              <div class="flex flex-row -space-x-2 shrink-0">
                {#each run.items[0].bandLineup ?? [] as m, i}
                  <img src={m.user_avatar || '/images/avatar-default.svg'} alt="" class="w-6 h-6 rounded-full border border-cold-base bg-base-900" style="z-index: {i + 1}" />
                {/each}
              </div>
              <span class="text-cold-light shrink-0">
                {#if isOpen}<ChevronUp size={18} />{:else}<ChevronDown size={18} />{/if}
              </span>
            </button>
            {#if isOpen}
            <div class="flex flex-col gap-[1px] mt-[1px]">
              {#each run.items as perf (perf.id)}
                <div class="bg-base-900" data-perf-id={perf.id}>
                  <a href={`/performance/${perf.id}`} class="px-4 py-2 flex items-baseline gap-3">
                    <span class="text-gray-400 text-xl font-medium w-7 shrink-0">{(perf.order ?? 0) + 1}</span>
                    <span class="text-yellow truncate">{getSongTitle(perf.song)}</span>
                    <span class="text-sm text-cold-light truncate ml-auto">{getSongArtist(perf.song)}</span>
                  </a>
                  {#if perf.band.pending && canApproveSong(perf)}
                    <div class="px-4 pb-2 flex items-center gap-3">
                      <span class="flex-1 text-xs text-yellow truncate">Aprobar a {perf.band.name}</span>
                      <button on:click={() => decideBandSignup(perf, 'approved')} aria-label="Aprobar banda" class="p-1 text-green-500 hover:text-green-400"><Check size={18} /></button>
                      <button on:click={() => decideBandSignup(perf, 'declined')} aria-label="Rechazar banda" class="p-1 text-red-500 hover:text-red-400"><X size={18} /></button>
                    </div>
                  {/if}
                </div>
              {/each}
            </div>
            {/if}
          </div>
        {:else}
        <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
          {#each run.items as perf, index (perf.id)}
            <li class="bg-base-900 px-4 p-3" data-perf-id={perf.id} class:flash-move={justMovedId === perf.id}>
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
                  <button on:click={() => removeSong(perf)} aria-label="Quitar del setlist" class="p-1 ml-1 text-warm-base hover:text-red-400 shrink-0"><Trash2 size={20} /></button>
                </div>
              {:else}
                <a href={`/performance/${perf.id}`} class="block">
                  <div class="flex items-center gap-2">
                    <span class="text-gray-400 text-3xl font-medium mr-2">{(perf.order ?? index) + 1}</span>
                    <div class="flex-1">
                      <PerformanceListItem
                        title={getSongTitle(perf.song)}
                        artist={getSongArtist(perf.song)}
                        key={perf.key}
                        performers={perf.performers || []}
                        band={perf.band}
                        lineup={perf.bandLineup || []}
                        highlightInstrumentIds={myInstrumentIds}
                      />
                    </div>
                  </div>
                </a>
                {#if perf.band && perf.band.pending && canApproveSong(perf)}
                  <div class="mt-2 flex items-center gap-3">
                    <span class="flex-1 text-sm text-yellow truncate">Aprobar a {perf.band.name}</span>
                    <button on:click={() => decideBandSignup(perf, 'approved')} aria-label="Aprobar banda" class="p-1 text-green-500 hover:text-green-400"><Check size={20} /></button>
                    <button on:click={() => decideBandSignup(perf, 'declined')} aria-label="Rechazar banda" class="p-1 text-red-500 hover:text-red-400"><X size={20} /></button>
                  </div>
                {/if}
                {#if !perf.band && canApproveSong(perf) && perf.pending && perf.pending.length}
                  <button on:click={() => toggleApprovals(perf.id)} class="mt-1 text-sm text-yellow flex items-center gap-1">
                    {perf.pending.length} por aprobar
                    {#if expandedApprovals.has(perf.id)}<ChevronUp size={16} />{:else}<ChevronDown size={16} />{/if}
                  </button>
                  {#if expandedApprovals.has(perf.id)}
                    <div class="mt-2 flex flex-col gap-3">
                      {#each pendingByInstrument(perf.pending) as group}
                        <div>
                          <div class="text-xs text-cold-light uppercase tracking-wide mb-1">{instrumentsById[group.instrument_id] ?? 'Instrumento'}</div>
                          {#each group.applicants as applicant}
                            <div class="flex items-center gap-2 py-1">
                              <img src={getUserAvatar(applicant.user_id)} alt="" class="w-6 h-6 rounded-full border border-cold-base" />
                              <span class="flex-1 text-white truncate">{getUserNickname(applicant.user_id)}</span>
                              <button on:click={() => decideSignup(perf, applicant, 'approved')} aria-label="Aprobar" class="p-1 text-green-500 hover:text-green-400"><Check size={20} /></button>
                              <button on:click={() => decideSignup(perf, applicant, 'declined')} aria-label="Rechazar" class="p-1 text-red-500 hover:text-red-400"><X size={20} /></button>
                            </div>
                          {/each}
                        </div>
                      {/each}
                    </div>
                  {/if}
                {/if}
              {/if}
            </li>
          {/each}
        </ul>
        {/if}
        {/each}
      </div>
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
      <ShareModal url={flyerUrl} title={party?.title} on:close={closeShareModal} />
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
