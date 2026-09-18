<script lang="ts">
  // Imports
  import { onMount, onDestroy, tick } from 'svelte';
  import { page } from '$app/state';
  import { goto, pushState, replaceState } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, ChevronUp, ChevronDown, Check, X, Share2, Edit, MapPin, Plus, Trash2, AlertTriangle, Copy, Users, Radio } from 'lucide-svelte';
  import PerformanceListItem from '../../../lib/components/PerformanceListItem.svelte';
  import { user } from '$lib/stores/user';
  import ShareModal from '$lib/components/ShareModal.svelte';
  import StatusBadge from '$lib/components/StatusBadge.svelte';
  import ApplauseButton from '$lib/components/ApplauseButton.svelte';
  import PerformanceDetail from '$lib/components/PerformanceDetail.svelte';
  import PartyLogistics from '$lib/components/PartyLogistics.svelte';
  import SongLineupApplause from '$lib/components/SongLineupApplause.svelte';
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
  // #110: the blocks a night is made of. A set is a real row now, not a run of
  // consecutive band_id — it survives a reorder, it can be empty (a booked band
  // with no songs yet), and one band can have two of them in one night.
  let sets: any[] = [];
  // Which of those sets THIS user may rearrange the contents of. Answered by
  // can_edit_set() rather than re-derived here, so the client cannot drift from
  // the rule the database enforces: the band for a band set, the organizer for
  // an open one.
  let editableSets = new Set<number>();
  let editableLoadedFor = '';
  let songs: any[] = [];
  let users: any[] = [];
  let partyPerformers: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;
  let currentUserId: string | null = null;
  let unsubscribeUser: () => void;
  let editMode = false;
  let setlistView: 'orden' | 'faltan' | 'para-ti' = 'orden'; // ephemeral view (#60)
  let justMovedId: number | null = null;
  let instrumentsById: Record<number, string> = {};
  let expandedApprovals = new Set<number>();
  let myInstrumentIds: number[] = []; // instruments the viewer plays (#32)
  let showShareModal = false;
  let partyAdmins: string[] = [];
  // Co-organizers as PRESENTED (order + who opted out), separate from the
  // permission list above. The creator is pinned first and isn't in this table,
  // so nothing here can reorder or hide them.
  let coOrganizers: { user_id: string; display_order: number | null; hidden: boolean }[] = [];
  // Who a requirement can be assigned to (#95 Stage 2): the people already
  // attached to this toque. Derived from data the page has, so the picker costs
  // no query — and scoping it here is why this never needs the unbounded
  // all-profiles fetch that #92 exists to remove.
  // `users` is named explicitly even though getUserNickname() reads it
  // internally: legacy mode tracks `$:` dependencies BY NAME, so without it this
  // would not recompute when profiles land and every name would read "Anónimo".
  // It happens to work today only because `users` is assigned a few lines before
  // partyPerformers — coupling too fragile to rely on.
  // Organizers only (creator + party_admin), for the "Organizador" auto-assign.
  // Same `users` caveat as below: named explicitly because getUserNickname reads
  // it and legacy mode tracks `$:` deps by NAME.
  $: logisticsOrganizers = [
    ...new Map(
      [...(party?.created_by ? [party.created_by] : []), ...partyAdmins]
        .filter(Boolean)
        .map((id: string) => [id, { id, nickname: users.length ? getUserNickname(id) : 'Anónimo' }])
    ).values()
  ];

  $: logisticsPeople = [
    ...new Map(
      [
        ...partyPerformers.map((p: any) => p.user_id),
        ...(party?.created_by ? [party.created_by] : []),
        ...partyAdmins
      ]
        .filter(Boolean)
        .map((id: string) => [id, { id, nickname: users.length ? getUserNickname(id) : 'Anónimo' }])
    ).values()
  ];

  $: shownOrganizers = party
    ? [
        party.created_by,
        ...coOrganizers
          .filter((a) => !a.hidden && a.user_id !== party.created_by)
          .sort((a, b) => (a.display_order ?? 9999) - (b.display_order ?? 9999))
          .map((a) => a.user_id)
      ].filter((id): id is string => !!id)
    : [];
  let venueAdmins: string[] = [];
  let usersLoaded = false;
  // In-app confirm/reason dialog (native prompt()/confirm() are blocked in some
  // browser contexts — mobile/webviews — where they throw and do nothing).
  let confirmDialog: {
    title: string;
    body?: string;
    // Optional consequence callout: what this action costs OTHER people, with
    // their faces, so it isn't an abstract line of text.
    warning?: string;
    people?: { user_id: string; avatar: string; name: string }[];
    withReason: boolean;
    confirmLabel: string;
    run: (note: string | null) => Promise<void> | void;
  } | null = null;
  let dialogNote = '';

  // Applause (#38, Stage A). Tallies are derived into MAPS rather than read via
  // helper functions: in legacy mode a `{fn(perf.id)}` in markup only re-runs when
  // something named in that expression changes, so a function closing over
  // `applause` would show stale counts. A map is named in the template.
  let applause: { id: number; target_type: string; performance_id: number | null; performer_id: string | null; from_user: string }[] = [];
  // Which song rows have their lineup open for per-musician claps (#38 Stage B).
  let openLineups = new Set<number>();
  let canApplaud = false;          // window open AND the viewer was there (RLS decides for real)
  let clapBusy = new Set<string>();

  async function loadApplause(pid: number) {
    const { data } = await supabase
      .from('applause')
      .select('id, target_type, performance_id, performer_id, from_user')
      .eq('party_id', pid);
    applause = (data ?? []) as any[];
  }

  $: songTally = (() => {
    const m: Record<number, { count: number; mine: number | null }> = {};
    for (const a of applause) {
      if (a.target_type !== 'song' || a.performance_id == null) continue;
      const e = (m[a.performance_id] ??= { count: 0, mine: null });
      e.count += 1;
      if (a.from_user === currentUserId) e.mine = a.id;
    }
    return m;
  })();
  $: eventTally = (() => {
    let count = 0, mine: number | null = null;
    for (const a of applause) {
      if (a.target_type !== 'event') continue;
      count += 1;
      if (a.from_user === currentUserId) mine = a.id;
    }
    return { count, mine };
  })();

  // Per-night performer claps, keyed by user.
  $: performerTally = (() => {
    const m: Record<string, { count: number; mine: number | null }> = {};
    for (const a of applause) {
      if (a.target_type !== 'performer' || !a.performer_id) continue;
      const e = (m[a.performer_id] ??= { count: 0, mine: null });
      e.count += 1;
      if (a.from_user === currentUserId) e.mine = a.id;
    }
    return m;
  })();
  // "You nailed THAT one" — keyed performance:user, so the same musician can be
  // clapped separately on each song they played.
  $: songPerformerTally = (() => {
    const m: Record<string, { count: number; mine: number | null }> = {};
    for (const a of applause) {
      if (a.target_type !== 'song_performer' || !a.performer_id || a.performance_id == null) continue;
      const e = (m[a.performance_id + ':' + a.performer_id] ??= { count: 0, mine: null });
      e.count += 1;
      if (a.from_user === currentUserId) e.mine = a.id;
    }
    return m;
  })();

  function toggleLineup(perfId: number) {
    const next = new Set(openLineups);
    next.has(perfId) ? next.delete(perfId) : next.add(perfId);
    openLineups = next;
  }

  // The window opens when the show starts — which happens over Realtime while
  // attendees already have this page open. Checking once on mount left them with
  // a Now Playing banner and no clap control until they reloaded, on exactly the
  // night the feature exists for. Re-check whenever the status moves.
  let applauseCheckedFor: string | null = null;
  async function refreshCanApplaud(pid: number) {
    const { data } = await supabase.rpc('can_applaud', { p_party: pid });
    canApplaud = !!data;
  }
  $: if (party?.id && party.status && party.status !== applauseCheckedFor) {
    applauseCheckedFor = party.status;
    refreshCanApplaud(party.id);
  }

  // Toggle: a clap is inserted or deleted, never edited. The unique indexes make
  // re-clapping clean, and RLS re-checks the window and target server-side.
  async function toggleClap(key: string, mine: number | null, row: Record<string, any>) {
    if (clapBusy.has(key) || !currentUserId || !party) return;
    clapBusy = new Set(clapBusy).add(key);
    try {
      const { error: e } = mine
        ? await supabase.from('applause').delete().eq('id', mine)
        : await supabase.from('applause').insert({ party_id: party.id, from_user: currentUserId, ...row } as any);
      if (e) { reportError(e); return; }
      await loadApplause(party.id);
    } catch {
      toastError('No se pudo conectar con el servidor.');
    } finally {
      const next = new Set(clapBusy); next.delete(key); clapBusy = next;
    }
  }
  const toggleEventClap = () => toggleClap('event', eventTally.mine, { target_type: 'event' });
  const toggleSongClap = (perf: any) =>
    toggleClap('song:' + perf.id, songTally[perf.id]?.mine ?? null, { target_type: 'song', performance_id: perf.id });
  const togglePerformerClap = (userId: string) =>
    toggleClap('performer:' + userId, performerTally[userId]?.mine ?? null,
               { target_type: 'performer', performer_id: userId });
  const toggleSongPerformerClap = (perfId: number, userId: string) =>
    toggleClap('sp:' + perfId + ':' + userId, songPerformerTally[perfId + ':' + userId]?.mine ?? null,
               { target_type: 'song_performer', performance_id: perfId, performer_id: userId });

  // Live mode (#37): the now-playing pointer is derived — the single performance
  // with live_state 'playing' is it. No pointer column to fall out of sync.
  $: isLive = party?.status === 'live';
  $: nowPlaying = isLive ? performances.find((p) => p.live_state === 'playing') ?? null : null;

  $: canAdmin = !!currentUserId && (party?.created_by === currentUserId || partyAdmins.includes(currentUserId));
  // Removing a song is allowed for a party admin OR the person who suggested it
  // (the RLS delete policy says exactly this — see migrations, #77). Reordering
  // stays admin-only, so edit mode can be useful to a non-admin with none of the
  // arrows: their own suggestions are still theirs to take back.
  function canRemoveSong(perf: any): boolean {
    return canAdmin || (!!currentUserId && perf?.suggested_by === currentUserId);
  }
  $: mySuggestionCount = currentUserId ? performances.filter((p) => p.suggested_by === currentUserId).length : 0;
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
  // the stored `order` (running order) is never touched. Edit mode always uses
  // the canonical order.
  $: displayed = editMode
    ? performances
    : setlistView === 'faltan'
      ? [...performances].sort((a, b) => openInstrumentIds(b).length - openInstrumentIds(a).length)
      : setlistView === 'para-ti'
        ? performances.filter((p) => openInstrumentIds(p).some((id) => myInstrumentIds.includes(id)))
        : performances;

  // Blocks come from party_set (#110). Previously they were inferred from a run
  // of consecutive band_id, which meant a block could not be moved as a unit,
  // could not be empty, and silently merged two sets by the same band.
  //
  // Grouping now stays on in EDIT mode too — that is the point of the feature.
  // The other views re-sort or filter, so blocks would be arbitrary there.
  $: grouping = setlistView === 'orden';
  $: blocks = grouping
    ? sets
        .map((st) => ({ set: st, band: st.band, items: displayed.filter((p) => p.set_id === st.id) }))
        // Keep an empty BAND block (a band booked but with no songs yet); an
        // empty open block is garbage-collected server-side and never shows.
        .filter((b) => b.items.length > 0 || !!b.band)
    : [{ set: null, band: null, items: displayed }];
  // A pure jam night is one block, and must look exactly as it does today — so
  // the per-block furniture (header, move arrows) only appears once a night
  // actually has more than one block.
  $: multiBlock = blocks.length > 1;
  // During a show the set holding the pointer is force-expanded and cannot be
  // collapsed: a closed box while the band is on stage is the opposite of what
  // live mode is for.
  $: liveSetId = nowPlaying?.set_id ?? null;

  // The row number is position in the NIGHT, counted across blocks — so moving a
  // band's block to the front renumbers everything after it. Derived rather than
  // stored: `performances` is kept sorted in running order, so its index IS the
  // position, and it recomputes on every move.
  $: nightIndexById = Object.fromEntries(performances.map((p: any, i: number) => [p.id, i]));

  // Re-asked whenever the viewer or the set list changes — keyed on both, so it
  // runs once per real change rather than on every realtime refresh. Logged out,
  // the answer is always false and no call is made.
  $: editableKey = currentUserId && sets.length ? `${currentUserId}:${sets.map((st) => st.id).join(',')}` : '';
  $: if (editableKey !== editableLoadedFor) refreshEditableSets(editableKey);

  async function refreshEditableSets(key: string) {
    editableLoadedFor = key;
    if (!key) { editableSets = new Set<number>(); return; }
    const forSets = [...sets];
    const res = await Promise.all(forSets.map((st) => supabase.rpc('can_edit_set', { sid: st.id })));
    // Another change may have landed while these were in flight; the key guard
    // makes the last one win rather than an older answer overwriting it.
    if (editableLoadedFor !== key) return;
    editableSets = new Set(forSets.filter((_, i) => res[i].data === true).map((st) => st.id));
  }

  // Is there anywhere for this song to go in that direction?
  //
  // For a loose song the answer is the whole night: UP is dead only on the first
  // song of the FIRST block, DOWN only on the last song of the LAST. Anywhere in
  // between there is somewhere to go — the song hops over a band's block if one
  // is in the way, and nudge_song creates an open block beyond it when the night
  // starts or ends with a band.
  //
  // A BAND block is the exception and stays bounded by itself: a band's songs
  // stay in the band's block, since pushing one out into the organizer's open
  // list is not the band's call (and can_edit_set would refuse it).
  function canNudge(run: any, index: number, dir: -1 | 1) {
    if (!run.set) return false;
    const inside = dir < 0 ? index > 0 : index < run.items.length - 1;
    if (inside) return true;
    if (run.band) return false;
    const bi = blocks.indexOf(run);
    return dir < 0 ? bi > 0 : bi < blocks.length - 1;
  }

  // The running order, as the database defines it: set first, then position
  // within the set. Used to re-sort locally after an optimistic move.
  function bySetThenOrder(a: any, b: any) {
    const sa = sets.find((x) => x.id === a.set_id)?.order ?? 9999;
    const sb = sets.find((x) => x.id === b.set_id)?.order ?? 9999;
    return sa - sb
      || (a.order ?? Number.MAX_SAFE_INTEGER) - (b.order ?? Number.MAX_SAFE_INTEGER)
      || a.id - b.id;
  }

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
        // `order` is renumbered 1..n across the whole copy rather than carried
        // over. Since #110 it means "position within a SET", so two songs in
        // different blocks share a value — and the byOrder map below, which
        // assumes it is unique per party, would then attach one song's lineup to
        // another. The copy lands as a single open block anyway (sets are not
        // copied), so a flat sequence is also the honest value.
        const rows = performances.map((p: any, i: number) => ({
          party: newId, song: p.song, key: p.key, ref_link: p.ref_link,
          order: i + 1, suggested_by: p.suggested_by ?? currentUserId
        }));
        const { data: newPerfs, error: perfErr } = await supabase.from('performance').insert(rows).select();
        if (perfErr) reportError(perfErr);
        else if (newPerfs) {
          // Map new performances back to their source by the sequence assigned
          // above, then copy each song's approved lineup. The status trigger
          // re-approves them (the cloner is the new draft's admin).
          const byOrder: Record<number, number> = {};
          for (const p of newPerfs) if (p.order != null) byOrder[p.order] = p.id;
          const signupRows: any[] = [];
          for (const [i, p] of performances.entries()) {
            const newPid = byOrder[i + 1];
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
  // the time the room actually eats between songs. Approximate by design — a
  // handful of catalog songs still sit at the default duration.
  //
  // The gap depends on WHO is playing, which is the whole point of blocks: a
  // band runs its own set back to back, while an open block swaps musicians
  // between every song. A band also has to get on and set up first, and that
  // changeover is charged to the band's own block so the night adds up without
  // anything having to model the space between blocks.
  const TRANSITION_BAND_MIN = 1;  // same musicians, straight into the next song
  const TRANSITION_OPEN_MIN = 2;  // different musicians every song
  const CHANGEOVER_MIN = 15;      // a band getting on stage and line-checking

  // `songList` is a parameter rather than a closure read because Svelte's legacy
  // mode tracks reactive dependencies BY NAME: a `$:` or template expression
  // that only mentions `blocks` would not recompute when `songs` arrives, and
  // the two land in separate waves of loadSetlist.
  function setMinutes(items: any[], isBand: boolean, songList: any[]): number {
    // An empty band block is a band with nothing listed yet. Charging it a
    // changeover would print "0 canciones · ~15 min", which reads as a bug.
    if (items.length === 0) return 0;
    const songMins = items.reduce((t, p) => t + (songList.find((s) => s.id === p.song)?.duration ?? 0), 0);
    const gap = isBand ? TRANSITION_BAND_MIN : TRANSITION_OPEN_MIN;
    return (isBand ? CHANGEOVER_MIN : 0) + songMins + (items.length - 1) * gap;
  }

  // The whole night, blocks and changeovers included. Named deps, same reason.
  $: nightMinutes = blocks.reduce((t, r) => t + setMinutes(r.items, !!r.band, songs), 0);
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

  // Setlist reordering (#59), one of the two things edit mode does (the other is
  // removing a song, #62). Up/down arrows, no drag. Swapping two adjacent items
  // and re-numbering is deterministic — no drag, no DOM↔data desync.
  //
  // One call to nudge_song (#110), which owns the whole rule about where a song
  // may land: swap inside the block, or hop OVER a band's block to the next open
  // one, or start a new open block when the night ends with a band. Keeping that
  // in the database means the client cannot offer a move the rule would refuse,
  // and there is no second copy of "skip over, never into" to drift.
  //
  // It also replaced one UPDATE round trip PER ROW on every move — fifteen
  // requests to shift one song in a fifteen-song list.
  async function moveSong(setId: number, index: number, dir: -1 | 1) {
    const block = blocks.find((b) => b.set?.id === setId);
    if (!block || !canNudge(block, index, dir)) return;
    const movedId = block.items[index].id;
    // A swap inside the block is applied optimistically so the row moves under
    // the finger. A hop between blocks is not: it can create, merge or delete
    // blocks, so the structure has to come back from the server.
    const inside = dir < 0 ? index > 0 : index < block.items.length - 1;
    if (inside) {
      const ordered = [...block.items];
      [ordered[index], ordered[index + dir]] = [ordered[index + dir], ordered[index]];
      ordered.forEach((p, i) => (p.order = i + 1));
      performances = [...performances].sort(bySetThenOrder);
    }
    // Flash the moved row. Remove the class, force a reflow on that row, then
    // re-add — the reliable way to restart a CSS animation regardless of whether
    // the keyed list moved this node up or down (a plain toggle can get coalesced).
    justMovedId = null;
    await tick();
    const el = document.querySelector(`[data-perf-id="${movedId}"]`) as HTMLElement | null;
    if (el) void el.offsetWidth;
    justMovedId = movedId;
    const { error: err } = await supabase.rpc('nudge_song', { p_performance: movedId, p_dir: dir });
    if (err) reportError(err);
    // Re-read after a hop (the blocks may have changed shape) or a refusal (the
    // optimistic order on screen is a lie).
    if (err || !inside) await loadSetlist(Number(page.params.id));
  }

  // Move a whole block in the running order (#110). Organizer only — the other
  // half of the split: they decide WHEN a band plays, the band decides what.
  // Takes the set ID, not its index: the markup iterates `blocks`, which can
  // differ from `sets` (an empty open block is filtered out), so an index from
  // one list is not an index into the other.
  async function moveSet(setId: number, dir: -1 | 1) {
    const index = sets.findIndex((st) => st.id === setId);
    const target = index + dir;
    if (index < 0 || target < 0 || target >= sets.length) return;
    const arr = [...sets];
    [arr[index], arr[target]] = [arr[target], arr[index]];
    arr.forEach((st, i) => (st.order = i + 1));
    sets = arr;
    performances = [...performances].sort(bySetThenOrder);
    const { error: err } = await supabase.rpc('reorder_sets', {
      p_party: Number(page.params.id),
      p_set_ids: arr.map((st) => st.id)
    });
    if (err) reportError(err);
    // ALWAYS re-read, not just on failure: reorder_sets normalises the night
    // afterwards, and moving a band's block out from between two open ones
    // MERGES them. The optimistic swap above cannot know that happened, so it
    // left two open blocks on screen until something else forced a reload.
    //
    // Predicting the merge in the client was the other option and is the wrong
    // one — it would be a second copy of a rule the database already owns, free
    // to drift from it. loadSetlist deliberately leaves editMode alone, so the
    // re-read is invisible apart from the blocks snapping together.
    await loadSetlist(Number(page.params.id));
  }

  // Everyone who loses their spot if this song goes — approved and pending alike,
  // minus whoever is doing the removing (losing your own spot is the point, not a
  // consequence to warn about).
  function affectedByRemoval(perf: any) {
    const ids = new Set<string>();
    for (const p of perf.performers ?? []) ids.add(p.user_id);
    for (const p of perf.pending ?? []) ids.add(p.user_id);
    if (currentUserId) ids.delete(currentUserId);
    return [...ids].map((id) => ({ user_id: id, avatar: getUserAvatar(id), name: getUserNickname(id) }));
  }

  // Remove a song from the setlist (#62). Party admins and the song's suggester
  // (RLS enforces it); the DELETE cascades to this song's signups. Confirm first,
  // naming who else is affected, and treat a 0-row delete as an RLS denial rather
  // than silent success.
  function removeSong(perf: any) {
    const people = affectedByRemoval(perf);
    const n = people.length;
    const warning = !n
      ? undefined
      : perf.band
        ? `La toca ${perf.band.name}. Al quitarla se cancela la participación de la banda.`
        : n === 1
          ? 'Ya hay un músico inscrito en esta canción y perderá su cupo.'
          : `Ya hay ${n} músicos inscritos en esta canción y perderán su cupo.`;
    openDialog({
      title: '¿Quitar esta canción del setlist?',
      body: `Se eliminará "${getSongTitle(perf.song)}" del setlist.`,
      warning,
      people,
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

  // Removing a band's block takes its songs with it — performance.set_id is ON
  // DELETE CASCADE, decided on the grounds that leaving ten unclaimed songs
  // behind only moves the cleanup to the organizer. So the confirm names the
  // count, and the people who lose a spot.
  function removeSet(block: any) {
    const n = block.items.length;
    const seen = new Set<string>();
    const people: { user_id: string; avatar: string; name: string }[] = [];
    for (const perf of block.items) {
      for (const p of affectedByRemoval(perf)) {
        if (!seen.has(p.user_id)) { seen.add(p.user_id); people.push(p); }
      }
    }
    const name = block.band?.name ?? 'la banda';
    openDialog({
      title: `¿Quitar a ${name} del toque?`,
      body: n
        ? `Se eliminarán también sus ${n} ${n === 1 ? 'canción' : 'canciones'} del setlist.`
        : 'Su bloque está vacío, así que no se pierde ninguna canción.',
      people,
      withReason: false,
      confirmLabel: 'Quitar',
      run: async () => {
        const { data, error: e } = await supabase
          .from('party_set').delete().eq('id', block.set.id).select('id');
        // Two different refusals. The live-show guard RAISES, so it arrives as a
        // real error with a message worth showing. RLS refusing is silent — 0
        // rows and no error, the PostgREST trap — so the row count is the only
        // way to tell it from success.
        if (e) { reportError(e); return; }
        if (!data || data.length === 0) { toastError('No tienes permiso para quitar este bloque.'); return; }
        toastSuccess(`${name} ya no toca en este toque.`);
        // Structure change: removing a block can leave two open blocks adjacent,
        // which the database merges. Re-read rather than guess at the result.
        await loadSetlist(Number(page.params.id));
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
    // The COUNT is public, the roster is not (#113): party_rsvp rows are now
    // readable only by their owner and the toque's organisers, so a head-count
    // over the table would return 1 or 0 instead of the total. The RPC is
    // DEFINER and counts everyone, while still refusing a toque you cannot see.
    const [countRes, mineRes] = await Promise.all([
      supabase.rpc('party_rsvp_count', { p_party: party.id }),
      currentUserId
        ? supabase.from('party_rsvp').select('user_id').eq('party_id', party.id).eq('user_id', currentUserId).maybeSingle()
        : Promise.resolve({ data: null })
    ]);
    rsvpCount = (countRes.data as number | null) ?? 0;
    iAmGoing = !!mineRes.data;
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
  // editMode / expandedApprovals, so an in-progress interaction isn't clobbered.
  let perfIdSet = new Set<number>(); // this party's performance ids, for filtering
  // Every load takes a ticket. Three sequential waves of queries sit between
  // reading the order and painting it — half a second or so — and nothing used
  // to stop an older load from finishing last and repainting a stale setlist
  // over a newer one. Whoever holds the newest ticket wins, regardless of who
  // finishes first.
  let loadSeq = 0;

  // `fromRealtime` marks a load nobody asked for: somebody else changed the
  // night. Those must NOT land while you are mid-edit — the deferral in
  // scheduleReload only stops such a load from STARTING, and one already in
  // flight when you open edit mode would still land on top of your reorder with
  // a snapshot taken before it. Reloads we request ourselves (after a refused
  // nudge, after moving a block) are exactly the ones that must land, because
  // the screen is knowingly a lie until they do.
  async function loadSetlist(pid: number, fromRealtime = false) {
    // Checked BEFORE taking a ticket, not just at the end. A realtime load that
    // is only going to defer must not cancel a user-initiated one: moveSong,
    // moveSet and removeSet all run in edit mode and re-read precisely because
    // the screen is a lie until they do. If such a load took a ticket and then
    // declined to paint, it would void that correction and leave the lie up
    // until the user left edit mode.
    if (fromRealtime && (editMode || confirmDialog)) { pendingReload = true; return; }
    const seq = ++loadSeq;
    // Called after every await, before anything is assigned.
    function stale(): boolean {
      if (seq !== loadSeq) return true;              // a newer load started
      if (fromRealtime && (editMode || confirmDialog)) {
        pendingReload = true;                        // try again when they finish
        return true;
      }
      return false;
    }
    // Ordered SERVER-side. Without this, PostgREST returns rows in physical
    // order, which an UPDATE changes (a new tuple version lands elsewhere) — so
    // start_show / advance_show visibly reshuffled the setlist. The id tiebreak
    // keeps it deterministic even if two rows share an order.
    // Two-level ordering (#110): the night is a sequence of SETS, a set is a
    // sequence of songs. Fetched in the same wave — party_set depends on nothing.
    const [perfRes, setRes] = await Promise.all([
      supabase
        .from('performance')
        .select('id, song, suggested_by, ref_link, key, order, band_id, set_id, live_state, started_at')
        .eq('party', pid)
        .order('order', { ascending: true, nullsFirst: false })
        .order('id', { ascending: true }),
      supabase
        .from('party_set')
        .select('id, band_id, order, title')
        .eq('party_id', pid)
        .order('order', { ascending: true })
        .order('id', { ascending: true })
    ]);
    if (stale()) return;
    const { data: perfData, error: perfErr } = perfRes;
    if (perfErr) { errorPerformances = perfErr.message; return; }
    if (setRes.error) { errorPerformances = setRes.error.message; return; }
    const setRows = (setRes.data ?? []) as any[];
    const setOrderById: Record<number, number> = Object.fromEntries(setRows.map((st) => [st.id, st.order]));
    // Sort by set first, then position within the set. A row whose set somehow
    // did not come back sorts last rather than jumping to the top.
    const perfs = (perfData ?? []).sort(
      (a, b) =>
        (setOrderById[a.set_id as number] ?? Number.MAX_SAFE_INTEGER) -
          (setOrderById[b.set_id as number] ?? Number.MAX_SAFE_INTEGER) ||
        (a.order ?? Number.MAX_SAFE_INTEGER) - (b.order ?? Number.MAX_SAFE_INTEGER) ||
        a.id - b.id
    );
    // NB: nothing is renumbered here. `order` means position within a SET now and
    // the reorder RPCs own it server-side, while the row number shown on screen
    // is derived (see nightIndexById) — it has to recompute after a move, which
    // a value baked in at load time does not.
    const songIds = [...new Set(perfs.map((p) => p.song).filter((x): x is number => x != null))];
    const userIds = [...new Set(perfs.map((p) => p.suggested_by).filter((x): x is string => x != null))];
    if (party?.created_by) userIds.push(party.created_by);
    // Co-organizers are named in the header and may appear nowhere else on the
    // page, so their profiles have to be fetched here too.
    userIds.push(...partyAdmins);
    // Band names for the setlist rows (#74) AND for the set headers (#110) — a
    // band block with no songs yet still has to say whose it is.
    const bandIds = [...new Set(
      [...perfs.map((p) => p.band_id), ...setRows.map((st) => st.band_id)]
        .filter((x): x is number => x != null)
    )];
    // One wave, not three: these depend on the performance rows but not on each
    // other. Each round trip to Supabase is ~175ms of pure latency, so serialising
    // them cost half a second for nothing.
    const [songRes, perfUserRes, bandRes] = await Promise.all([
      songIds.length ? supabase.from('song').select('id, title, artist, duration').in('id', songIds) : Promise.resolve({ data: [] as any[] }),
      perfs.length ? supabase.from('performance_user').select('user_id, instrument_id, performance_id, status, band_id').in('performance_id', perfs.map((p) => p.id)) : Promise.resolve({ data: [] as any[] }),
      bandIds.length ? supabase.from('band').select('id, name, avatar_url').in('id', bandIds) : Promise.resolve({ data: [] as any[] })
    ]);
    const songData = songRes.data;
    const perfUsers = perfUserRes.data;
    const bandData = bandRes.data;
    const bandsById: Record<number, any> = Object.fromEntries((bandData ?? []).map((b: any) => [b.id, b]));
    const performerUserIds = [...new Set((perfUsers ?? []).map((p) => p.user_id))];
    const allUserIds = [...new Set([...userIds, ...performerUserIds])];
    const { data: userData } = allUserIds.length ? await supabase.from('profile').select('id, nickname, avatarUrl: avatar_url').in('id', allUserIds) : { data: [] as any[] };
    // The one that matters: everything below assigns shared state.
    if (stale()) return;
    songs = songData ?? [];
    users = userData ?? [];
    usersLoaded = true;
    sets = setRows.map((st) => ({
      ...st,
      band: st.band_id
        ? {
            id: st.band_id,
            name: bandsById[st.band_id]?.name ?? 'Banda',
            avatar_url: bandsById[st.band_id]?.avatar_url ?? null
          }
        : null
    }));
    // editableSets is filled by the reactive block near the top rather than here:
    // the user store can resolve AFTER this first load, and a band member whose
    // uid landed late would otherwise sit there with no controls until a reload.

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
      // Unique musicians on this song, resolved for display, for per-musician
      // applause (#38 Stage B). `performers` has one row per instrument, so the
      // same person can appear twice — dedupe here rather than in markup.
      const instrOf: Record<string, string> = {};
      for (const r of performers) {
        const n = instrumentsById[r.instrument_id];
        if (n) instrOf[r.user_id] = instrOf[r.user_id] ? instrOf[r.user_id] + ', ' + n : n;
      }
      const seenClap = new Set<string>();
      const clapLineup = (band ? bandLineup : performers)
        .filter((r: any) => (seenClap.has(r.user_id) ? false : (seenClap.add(r.user_id), true)))
        .map((r: any) => ({
          user_id: r.user_id,
          name: getUserNickname(r.user_id),
          avatar: getUserAvatar(r.user_id),
          instruments: instrOf[r.user_id] ?? ''
        }));
      return { ...perf, performers, pending, band, bandLineup, clapLineup };
    })
    // Hide a fully-declined band-owned song (band-or-nothing, #74).
    .filter((p) => !(p.band && p.band.declined));
    perfIdSet = new Set(performances.map((p) => p.id));
  }

  // Live setlist (#63): another user's signup/approval/song-change refreshes the
  // list. Defer while the viewer is mid-edit or has a dialog open, then flush.
  let setlistChannel: any = null;
  let pendingReload = false;
  // Debounced, because one edit is rarely one event: nudge_song used to renumber
  // a whole block, so a single tap on a ten-song set arrived here ten times and
  // started ten full reloads. Even with that fixed a burst is normal — a band
  // adding songs, a signup approved — and a reload is three round trips.
  let reloadTimer: ReturnType<typeof setTimeout> | null = null;
  function scheduleReload() {
    if (editMode || confirmDialog) { pendingReload = true; return; }
    if (reloadTimer) clearTimeout(reloadTimer);
    reloadTimer = setTimeout(() => { reloadTimer = null; loadSetlist(Number(page.params.id), true); }, 250);
  }
  $: if (pendingReload && !editMode && !confirmDialog) { pendingReload = false; loadSetlist(Number(page.params.id), true); }
  function subscribeSetlist(pid: number) {
    setlistChannel = supabase
      .channel(`setlist-${pid}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'performance', filter: `party=eq.${pid}` }, () => scheduleReload())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'performance_user' }, (payload: any) => {
        const rid = payload.new?.performance_id ?? payload.old?.performance_id;
        if (rid && perfIdSet.has(rid)) scheduleReload();
      })
      // Live mode (#37): `party` joined the realtime publication so a show
      // starting or ending flips this page over without a reload.
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'party', filter: `id=eq.${pid}` }, (payload: any) => {
        if (payload.new) party = { ...party, ...payload.new };
      })
      .subscribe();
  }

  // Lifecycle
  onMount(async () => {
    unsubscribeUser = user.subscribe(u => {
      currentUserId = u?.id ?? null;
    });
    const pid = Number(page.params.id);
    // This page used to make FOURTEEN sequential round trips (~2.9s measured), each
    // one ~175ms of pure latency waiting on the last. Most of them never depended
    // on each other. Batched into dependency waves below.
    //
    // Wave 1: everything that needs only the party id. `instrument` is a static
    // lookup; the party/admin rows gate the rest.
    // maybeSingle: a toque hidden by RLS is "not found", not a 406 whose raw
    // English message would land in front of the user.
    const [partyRes, adminRes, instrRes] = await Promise.all([
      supabase.from('party').select('*').eq('id', pid).maybeSingle(),
      supabase.from('party_admin').select('user_id, display_order, hidden').eq('party_id', pid),
      supabase.from('instrument').select('id, name')
    ]);
    const { data, error: err } = partyRes;
    const adminData = adminRes.data;
    party = data;
    partyAdmins = adminData ? adminData.map((a: any) => a.user_id) : [];
    coOrganizers = adminData ?? [];
    instrumentsById = Object.fromEntries((instrRes.data ?? []).map((i: any) => [i.id, i.name]));

    if (err) {
      error = 'No se pudo cargar el toque. Revisa tu conexión e intenta de nuevo.';
    } else if (!data) {
      error = 'No encontramos este toque, o no tienes acceso. ¿Iniciaste sesión?';
    } else {
      party = data;
      // Wave 2: the venue pair, the setlist, applause, RSVP and the viewer's own
      // instruments all in flight together — none of them needs another's result.
      // loadSetlist internally does its own two waves.
      await Promise.all([
        party?.venue
          ? Promise.all([
              supabase.from('venue').select('id, name, area, requires_approval, created_by').eq('id', party.venue).maybeSingle(),
              supabase.from('venue_admin').select('user_id').eq('venue_id', party.venue)
            ]).then(([venueRes, vAdminRes]) => {
              if (!venueRes.error) venue = venueRes.data;
              venueAdmins = (vAdminRes.data ?? []).map((a: any) => a.user_id);
            })
          : Promise.resolve(),
        loadSetlist(pid),
        loadApplause(pid),
        loadRsvp(),
        // The viewer's own instruments (#32) — powers the personalized gap alert
        // + the "you could play here" highlight on open slots.
        currentUserId
          ? supabase.from('profile_instrument').select('instrument_id').eq('profile_id', currentUserId)
              .then(({ data: pi }) => { myInstrumentIds = (pi ?? []).map((r: any) => r.instrument_id); })
          : Promise.resolve()
      ]);
      loadingPerformances = false;
      subscribeSetlist(pid);
    }
    loading = false;
    await scrollToSetlistIfRequested();
  });

  // Shallow routing (#94). Opening a song used to navigate, which UNMOUNTED this
  // page — so coming back re-ran onMount and refetched everything: 16 requests,
  // ~1s, on every single signup. It was never a document reload (navigation is
  // client-side already); it was a remount.
  //
  // pushState puts the song's URL in the address bar and renders the detail as an
  // overlay instead, so this page stays mounted. Two things fall out of that:
  // its state survives, and so does the realtime channel — which means a signup
  // made in the overlay flows back into the setlist through the subscription that
  // was already there, with no refetch on close at all.
  //
  // The <a href> is kept and only its plain-left-click is intercepted, so
  // cmd/ctrl/middle-click still open a real tab and the URL stays shareable.
  function openSong(e: MouseEvent, perfId: number) {
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey || e.button !== 0) return;
    e.preventDefault();
    pushState(`/performance/${perfId}`, { perfId });
  }

  // Close = go back, so the history entry pushState created is consumed and the
  // browser's own back button behaves identically to this button.
  function closeSong() {
    history.back();
  }

  // Lock the page behind the overlay so a scroll gesture doesn't run the setlist
  // underneath it, and release it on close.
  //
  // This is an ACTION, not a `$:` statement, and that's deliberate. `page` comes
  // from $app/state and is never reassigned — only its internal rune state
  // changes — so in this legacy-mode component a `$:` reading `page.state` runs
  // once at init and never again. (The template's {#if page.state.perfId} does
  // work, because template expressions track rune reads; `$:` tracks variable
  // NAMES.) Tying it to the overlay element's own lifecycle sidesteps the whole
  // question and correctly releases on browser-back too, which no close handler
  // of ours would see.
  function lockScroll(_node: HTMLElement) {
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return { destroy() { document.body.style.overflow = previous; } };
  }

  // Escape closes it, as any dialog should.
  // <svelte:window> has to be top-level, so this is always bound and checks for
  // itself whether the overlay is actually up.
  function overlayKeydown(e: KeyboardEvent) {
    if (e.key === 'Escape' && page.state.perfId) closeSong();
  }

  // Coming back from "agregar canciones" or a song's own page, land on the
  // SETLIST rather than the top of the toque — the next thing you want is to
  // sign up for another song, and the header + description can be a full screen
  // of scrolling in the way. Opt-in via #setlist so a normal visit still opens
  // at the top.
  let setlistEl: HTMLElement;
  async function scrollToSetlistIfRequested() {
    if (typeof window === 'undefined' || window.location.hash !== '#setlist') return;
    // The setlist only exists in the DOM once `loading` is false.
    await tick();
    if (!setlistEl) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    setlistEl.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'start' });
    // Drop the hash so a later refresh doesn't re-jump.
    //
    // MUST be SvelteKit's replaceState, not the native one. `history
    // .replaceState({}, ...)` overwrites the entry's state object, wiping the
    // sveltekit:history / sveltekit:states bookkeeping — and shallow routing
    // (#94) reads exactly that to restore page.state on popstate. With it gone,
    // closing the song overlay consumed a history entry WITHOUT clearing
    // page.state.perfId, so the first back appeared to do nothing and the second
    // jumped somewhere unexpected. Reported from a phone; reproduced locally.
    replaceState(window.location.pathname + window.location.search, {});
  }

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser();
    if (setlistChannel) supabase.removeChannel(setlistChannel);
    // A pending reload would otherwise fire against a page that is gone.
    if (reloadTimer) clearTimeout(reloadTimer);
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
      <!-- "Confirmado" tells a visitor nothing they can't already infer from being
           here — a confirmed toque is just the normal case. Every other status
           does carry information (a draft, a pending approval, a cancellation),
           so the badge stays for those. PartyListItem now applies the same rule,
           so a list never shows "Confirmado" either. -->
      {#if party.status !== 'confirmed'}
        <StatusBadge status={party.status} />
      {/if}
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
    <!-- The organizer's "Cancelar toque" used to float here for every confirmed
         toque. It's a rare, destructive action and only admins ever saw it, so it
         now lives in the edit view instead of sitting on the page everyone reads.
         The contextual ones below/above stay: they're part of a decision the
         viewer is actually being asked to make. -->
    {:else if isVenueAdmin && !canAdmin && (party.status === 'confirmed' || party.status === 'live')}
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
    <!-- Live mode (#37): during a show this is the most important thing on the
         page, so it sits above everything but the title. Streams over Realtime. -->
    {#if isLive}
      <div class="rounded-lg overflow-clip border border-warm-base/40">
        <div class="bg-base-900 px-4 py-3">
          <span class="inline-flex items-center gap-1.5 text-xs uppercase tracking-widest text-warm-base">
            <span class="w-2 h-2 rounded-full bg-warm-base animate-pulse"></span> Sonando ahora
          </span>
          {#if nowPlaying}
            <div class="mt-1 text-xl text-yellow leading-tight">{getSongTitle(nowPlaying.song)}</div>
            <div class="text-sm text-cold-light">{getSongArtist(nowPlaying.song)}</div>
            {#if nowPlaying.band}
              <div class="mt-1 text-sm text-white inline-flex items-center gap-1.5"><Users size={14} /> {nowPlaying.band.name}</div>
            {/if}
            <!-- Clapping opens the moment the song starts — you don't wait for it
                 to finish (principle 3). -->
            {#if canApplaud && nowPlaying.live_state !== 'skipped'}
              {@const tally = songTally[nowPlaying.id]}
              <div class="mt-3">
                <ApplauseButton size="md" count={tally?.count ?? 0} clapped={!!tally?.mine}
                                busy={clapBusy.has('song:' + nowPlaying.id)}
                                label={getSongTitle(nowPlaying.song)}
                                on:toggle={() => toggleSongClap(nowPlaying)} />
              </div>
            {/if}
          {:else}
            <div class="mt-1 text-white text-sm">Entre canciones.</div>
          {/if}
        </div>
      </div>
    {/if}
    {#if canAdmin && (isLive || party.status === 'confirmed')}
      <a href={`/parties/${party.id}/live`} class="self-start inline-flex items-center gap-2 text-sm rounded-lg px-3 py-1.5 transition {isLive ? 'bg-warm-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">
        <Radio size={16} /> {isLive ? 'Dirigir el show' : 'Empezar el show'}
      </a>
    {/if}
    <div class="flex flex-wrap items-center gap-x-1 gap-y-1">
      <span>{shownOrganizers.length > 1 ? 'Organizan:' : 'Organizado por:'}</span>
      {#if usersLoaded}
        {#each shownOrganizers as organizerId, i (organizerId)}
          <span class="inline-flex items-center">
            <img src={getUserAvatar(organizerId)} alt="" class="w-5 h-5 border-yellow rounded-full inline-block mx-2" />
            <span class="text-cold-light">{getUserNickname(organizerId)}</span>{#if i < shownOrganizers.length - 1}<span class="text-cold-light/50">,</span>{/if}
          </span>
        {/each}
      {/if}
    </div>
    <div class="text-lg mb-2 text-white">{party.description}</div>
    <div class="mb-2 text-white">{dayjs(party.date).locale('es').format('ddd D [de] MMMM, YYYY')}</div>
    <div class="mb-2 text-cold-light"><MapPin class="inline-block" size={18} /> {venue ? venue.name : 'Cargando...'}{venue?.area ? ` - ${venue.area}` : ''}</div>
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
    <!-- The whole-night clap. Shown once the show is on or done; before that
         there is nothing to applaud yet. -->
    {#if canApplaud || eventTally.count}
      <div class="flex items-center gap-3 bg-base-900 rounded-lg px-4 py-3">
        <div class="flex-1 min-w-0">
          <div class="text-white text-sm">¿Qué tal estuvo el toque?</div>
          <div class="text-cold-light text-xs">
            {eventTally.count === 0
              ? 'Sé el primero en aplaudir'
              : eventTally.count === 1 ? '1 persona aplaudió la noche' : eventTally.count + ' personas aplaudieron la noche'}
          </div>
        </div>
        <ApplauseButton size="md" count={eventTally.count} clapped={!!eventTally.mine}
                        busy={clapBusy.has('event')} readOnly={!canApplaud}
                        label="la noche" on:toggle={toggleEventClap} />
      </div>
    {/if}
    <div class="mt-2 w-full flex items-center">
      <button on:click={handleShare} class="bg-cold-base text-white rounded-lg p-2 px-6 inline-flex items-center gap-2 m-auto">
        Compartir
        <Share2 class="w-5 h-5" />
      </button>
    </div>
    <div bind:this={setlistEl} class="flex items-center justify-between mt-4 mb-2 scroll-mt-4">
      <div>
        <h3 class="text-3xl text-white font-medium tracking-widest">SETLIST</h3>
        <!-- The night's running time. Open blocks stay plain rows on purpose, so
             this is the one place the time they take — and the changeover each
             band needs — is visible at all. -->
        {#if performances.length > 0}
          <span class="text-cold-light text-xs uppercase tracking-wide">~{formatMinutes(nightMinutes)} en total</span>
        {/if}
      </div>
      <!-- Edit mode covers removing a song as well as reordering, so it must be
           reachable with a single song too (reordering just has nothing to do),
           and by a non-admin who suggested at least one song — they can take their
           own back even though the arrows aren't theirs to use. -->
      <!-- ...and by a band member with a set of their own to arrange (#110), who
           may be neither an admin nor the suggester of anything here. Without
           this they can own a block and have no way to open the controls. -->
      {#if performances.length > 0 && (canAdmin || mySuggestionCount > 0 || editableSets.size > 0)}
        <button on:click={() => { editMode = !editMode; if (editMode) setlistView = 'orden'; }} class="text-cold-light text-sm border border-cold-light/40 hover:border-cold-light rounded-lg px-3 py-1 transition">
          {editMode ? 'Listo' : 'Editar'}
        </button>
      {/if}
    </div>
    {#if !editMode && !loadingPerformances && performances.length > 1}
      <div class="flex flex-wrap gap-2 mb-2">
        <button on:click={() => setlistView = 'orden'} class="text-xs rounded-full px-3 py-1 transition {setlistView === 'orden' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">Orden</button>
        <button on:click={() => setlistView = 'faltan'} class="text-xs rounded-full px-3 py-1 transition {setlistView === 'faltan' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">Faltan primero</button>
        {#if myInstrumentIds.length}
          <button on:click={() => setlistView = 'para-ti'} class="text-xs rounded-full px-3 py-1 transition {setlistView === 'para-ti' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">Para ti</button>
        {/if}
      </div>
    {/if}
    {#if !editMode && !loadingPerformances && songsWithGaps > 0}
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
        {#each blocks as run (run.set?.id ?? 'flat')}
        {@const canEditThis = !!run.set && editableSets.has(run.set.id)}
        {@const setIndex = run.set ? sets.indexOf(run.set) : -1}
        {#if run.band}
          <!-- Band block (#74 visuals, #110 backing). The block is a party_set
               row now, so it survives a reorder and can be empty. -->
          {@const setKey = run.set.id}
          {@const bandPending = run.items.some((p) => p.band?.pending)}
          {@const needsAction = run.items.some((p) => p.band?.pending && canApproveSong(p))}
          <!-- Force-expanded while it holds the now-playing pointer: a closed box
               with the band on stage is the opposite of what live mode is for.
               Also expanded in edit mode, since you cannot reorder what you
               cannot see. -->
          {@const isOpen = expandedSets.has(setKey) || needsAction || setKey === liveSetId || editMode}
          <div class="rounded-lg overflow-clip border-l-2 border-cold-base">
            <div class="w-full bg-base-900 px-4 py-2.5 flex items-center gap-3">
            <!-- The toggle is its own button so the move arrows are not nested
                 inside it (a button inside a button swallows the tap). -->
            <button type="button" on:click={() => toggleSet(setKey)} disabled={setKey === liveSetId}
                    class="flex items-center gap-3 flex-1 min-w-0 text-left disabled:cursor-default">
              {#if run.band.avatar_url}
                <img src={run.band.avatar_url} alt="" class="w-9 h-9 rounded-full object-cover border border-cold-base shrink-0" />
              {:else}
                <span class="w-9 h-9 rounded-full bg-base-950 border border-cold-base flex items-center justify-center shrink-0"><Users size={16} class="text-cold-light" /></span>
              {/if}
              <div class="flex-1 min-w-0">
                <span class="text-white truncate block">{run.band.name}</span>
                <span class="text-cold-light text-xs uppercase tracking-wide">
                  {run.items.length} {run.items.length === 1 ? 'canción' : 'canciones'} · ~{formatMinutes(setMinutes(run.items, true, songs))}{#if bandPending} · <span class="text-yellow">pendiente</span>{/if}
                </span>
              </div>
              <div class="flex flex-row -space-x-2 shrink-0">
                {#each run.items[0]?.bandLineup ?? [] as m, i}
                  <img src={m.user_avatar || '/images/avatar-default.svg'} alt="" class="w-6 h-6 rounded-full border border-cold-base bg-base-900" style="z-index: {i + 1}" />
                {/each}
              </div>
              <span class="text-cold-light shrink-0">
                {#if isOpen}<ChevronUp size={18} />{:else}<ChevronDown size={18} />{/if}
              </span>
            </button>
            <!-- Moving the BLOCK is the organizer's (#110): they decide when a
                 band plays, the band decides what it plays. -->
            {#if editMode && canAdmin && multiBlock}
              <div class="flex flex-col shrink-0 border-l border-cold-light/20 pl-2">
                <button on:click={() => moveSet(setKey, -1)} disabled={setIndex === 0} aria-label="Subir esta banda en el orden" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronUp size={20} /></button>
                <button on:click={() => moveSet(setKey, 1)} disabled={setIndex === sets.length - 1} aria-label="Bajar esta banda en el orden" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronDown size={20} /></button>
              </div>
            {/if}
            <!-- Un-booking the band is the organizer's, like placing them — the
                 other half of "the organizer decides WHEN a band plays". It is
                 also their only remedy if a band goes quiet, since they cannot
                 touch the block's contents. -->
            {#if editMode && canAdmin}
              <button on:click={() => removeSet(run)} aria-label={`Quitar a ${run.band.name} del toque`} class="p-1 ml-1 text-warm-base hover:text-red-400 shrink-0"><Trash2 size={20} /></button>
            {/if}
            </div>
            {#if isOpen}
            <div class="flex flex-col gap-[1px] mt-[1px]">
              {#each run.items as perf, i (perf.id)}
                {@const tally = songTally[perf.id]}
                <!-- Same reorder cue as an open song (#59). The row already had
                     data-perf-id, so moveSong's reflow trick found it and the
                     flash simply never fired: the class binding was missing.
                     Settles to base-900, which is this row's own background. -->
                <div class="bg-base-900" data-perf-id={perf.id} class:flash-move={justMovedId === perf.id}>
                  <!-- The clap sits BESIDE the link, never inside it: a button
                       nested in an anchor is invalid and swallows the tap. -->
                  <div class="flex items-center gap-2 pr-3">
                    <a href={`/performance/${perf.id}`} class="px-4 py-2 flex items-baseline gap-3 flex-1 min-w-0">
                      <span class="text-gray-400 text-xl font-medium w-7 shrink-0">{nightIndexById[perf.id] + 1}</span>
                      <span class="text-yellow truncate">{getSongTitle(perf.song)}</span>
                      <span class="text-sm text-cold-light truncate ml-auto">{getSongArtist(perf.song)}</span>
                    </a>
                    <!-- Rearranging a band's own set: only the band, never the
                         organizer (can_edit_set decides, asked at load). -->
                    {#if editMode && canEditThis && run.items.length > 1}
                      <div class="flex flex-col shrink-0">
                        <button on:click={() => moveSong(setKey, i, -1)} disabled={!canNudge(run, i, -1)} aria-label="Subir" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronUp size={20} /></button>
                        <button on:click={() => moveSong(setKey, i, 1)} disabled={!canNudge(run, i, 1)} aria-label="Bajar" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronDown size={20} /></button>
                      </div>
                    {/if}
                    {#if canApplaud && perf.started_at && perf.live_state !== 'skipped'}
                      <ApplauseButton count={tally?.count ?? 0} clapped={!!tally?.mine}
                                      busy={clapBusy.has('song:' + perf.id)} label={getSongTitle(perf.song)}
                                      on:toggle={() => toggleSongClap(perf)} />
                    {:else if tally?.count}
                      <ApplauseButton count={tally.count} readOnly />
                    {/if}
                      {#if perf.clapLineup?.length}
                        <button type="button" on:click={() => toggleLineup(perf.id)}
                                aria-expanded={openLineups.has(perf.id)}
                                aria-label={'Quiénes tocaron ' + getSongTitle(perf.song)}
                                class="p-1.5 text-cold-light/70 hover:text-white transition shrink-0">
                          <Users size={16} />
                        </button>
                      {/if}
                  </div>
                  {#if openLineups.has(perf.id)}
                    <SongLineupApplause perfId={perf.id} lineup={perf.clapLineup ?? []}
                                        tallies={songPerformerTally} busy={clapBusy}
                                        canApplaud={canApplaud && !!perf.started_at && perf.live_state !== 'skipped'}
                                        on:toggle={(e) => toggleSongPerformerClap(perf.id, e.detail)} />
                  {/if}
                  {#if perf.band.pending && canApproveSong(perf)}
                    <div class="px-4 pb-2 flex items-center gap-3">
                      <span class="flex-1 text-xs text-yellow truncate">Aprobar a {perf.band.name}</span>
                      <button on:click={() => decideBandSignup(perf, 'approved')} aria-label="Aprobar banda" class="p-1 text-green-500 hover:text-green-400"><Check size={18} /></button>
                      <button on:click={() => decideBandSignup(perf, 'declined')} aria-label="Rechazar banda" class="p-1 text-red-500 hover:text-red-400"><X size={18} /></button>
                    </div>
                  {/if}
                </div>
              {/each}
              <!-- The band's own `+` (#110). Positional rather than inferred: a
                   `+` inside Pulse's block adding to Pulse's set needs no
                   explanation, where one shared button that silently routes by
                   who pressed it behaves differently for different people.
                   Shown to whoever may edit this block — the band. -->
              {#if canEditThis}
                <a href={`/performance/create?partyId=${party.id}&band=${run.band.id}`}
                   class="bg-base-900 text-cold-light hover:text-white text-sm text-center py-2 transition">
                  Agregar una canción a {run.band.name} <Plus size={15} class="inline-block" />
                </a>
              {/if}
            </div>
            {/if}
          </div>
        {:else}
        <!-- Open songs stay plain rows, so a pure jam night looks exactly as it
             did. The handle for moving the block only appears in edit mode, and
             only once a night actually has more than one block. -->
        {#if editMode && canAdmin && multiBlock && run.set}
          <div class="flex items-center gap-2 px-1 pt-1">
            <span class="text-xs uppercase tracking-wide text-cold-light">Abiertas</span>
            <div class="ml-auto flex flex-row shrink-0">
              <button on:click={() => moveSet(run.set.id, -1)} disabled={setIndex === 0} aria-label="Subir este bloque" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronUp size={20} /></button>
              <button on:click={() => moveSet(run.set.id, 1)} disabled={setIndex === sets.length - 1} aria-label="Bajar este bloque" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronDown size={20} /></button>
            </div>
          </div>
        {/if}
        <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
          {#each run.items as perf, index (perf.id)}
            <li class="bg-base-900 px-4 p-3" data-perf-id={perf.id} class:flash-move={justMovedId === perf.id}
                class:border-l-2={isLive && perf.live_state === 'playing'}
                class:border-warm-base={isLive && perf.live_state === 'playing'}>
              {#if editMode}
                <div class="flex items-center gap-2">
                  <span class="text-gray-400 text-2xl font-medium mr-2 w-7 text-center shrink-0">{nightIndexById[perf.id] + 1}</span>
                  <div class="flex-1 min-w-0">
                    <div class="text-lg text-yellow truncate">{getSongTitle(perf.song)}</div>
                    <div class="text-sm text-cold-light truncate">{getSongArtist(perf.song)}</div>
                  </div>
                  <!-- At the edge of an open block these carry the song OVER the
                       next band block into the following open one (#110) — the
                       arrows stay live as long as somewhere exists to go. -->
                  {#if canEditThis && (run.items.length > 1 || multiBlock)}
                    <div class="flex flex-col shrink-0">
                      <button on:click={() => moveSong(run.set.id, index, -1)} disabled={!canNudge(run, index, -1)} aria-label="Subir" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronUp size={22} /></button>
                      <button on:click={() => moveSong(run.set.id, index, 1)} disabled={!canNudge(run, index, 1)} aria-label="Bajar" class="p-1 text-cold-light hover:text-white disabled:opacity-30"><ChevronDown size={22} /></button>
                    </div>
                  {/if}
                  {#if canRemoveSong(perf)}
                    <button on:click={() => removeSong(perf)} aria-label="Quitar del setlist" class="p-1 ml-1 text-warm-base hover:text-red-400 shrink-0"><Trash2 size={20} /></button>
                  {:else}
                    <!-- Not yours to remove: keep the row's shape so the list stays
                         aligned instead of the title stretching into the gap. -->
                    <span class="w-7 shrink-0" aria-hidden="true"></span>
                  {/if}
                </div>
              {:else}
                {@const tally = songTally[perf.id]}
                <div class="flex items-center gap-2">
                  <a href={`/performance/${perf.id}`} on:click={(e) => openSong(e, perf.id)} class="block flex-1 min-w-0">
                    <div class="flex items-center gap-2">
                      <span class="text-gray-400 text-3xl font-medium mr-2">{nightIndexById[perf.id] + 1}</span>
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
                  {#if canApplaud && perf.started_at && perf.live_state !== 'skipped'}
                    <ApplauseButton count={tally?.count ?? 0} clapped={!!tally?.mine}
                                    busy={clapBusy.has('song:' + perf.id)} label={getSongTitle(perf.song)}
                                    on:toggle={() => toggleSongClap(perf)} />
                  {:else if tally?.count}
                    <ApplauseButton count={tally.count} readOnly />
                  {/if}
                    {#if perf.clapLineup?.length}
                      <button type="button" on:click={() => toggleLineup(perf.id)}
                              aria-expanded={openLineups.has(perf.id)}
                              aria-label={'Quiénes tocaron ' + getSongTitle(perf.song)}
                              class="p-1.5 text-cold-light/70 hover:text-white transition shrink-0">
                        <Users size={16} />
                      </button>
                    {/if}
                </div>
                {#if openLineups.has(perf.id)}
                  <SongLineupApplause perfId={perf.id} lineup={perf.clapLineup ?? []}
                                    tallies={songPerformerTally} busy={clapBusy}
                                    canApplaud={canApplaud && !!perf.started_at && perf.live_state !== 'skipped'}
                                    on:toggle={(e) => toggleSongPerformerClap(perf.id, e.detail)} />
                {/if}
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
      {#if !editMode}
        <a href={`/performance/create?partyId=${party.id}`} class="w-full bg-cold-base text-white p-3 inline-block text-center">Sugerir una canción <Plus class="inline-block" /></a>
      {/if}
    </div>
    <!-- Event logistics (#95). Renders nothing for non-admins, and fetches
         nothing either — the common case pays zero for it. Sits after the
         setlist because you plan gear once you know what you're playing. -->
    <PartyLogistics partyId={party.id} venueId={party.venue} canAdmin={canAdmin}
      currentUserId={currentUserId} people={logisticsPeople} organizers={logisticsOrganizers} />

    <h3 class="text-3xl text-white font-medium pt-4 mt-2">MÚSICOS</h3>
    <div class="bg-base-950 rounded-lg overflow-hidden mt-2">
      <ul class="space-y-[1px]">
        {#each partyPerformers as performer}
          {@const pTally = performerTally[performer.user_id]}
          <li class="flex flex-col bg-base-900 gap-2 p-4">
            <div class="flex flex-row gap-2 items-center">
                <img src={getUserAvatar(performer.user_id)} alt="Avatar" class="w-6 h-6 rounded-full" />
                <span class="text-cold-light font-semibold flex-1 min-w-0 truncate">{getUserNickname(performer.user_id)}</span>
                <!-- "You were great tonight" — the whole-night clap for a musician. -->
                {#if canApplaud}
                  <ApplauseButton count={pTally?.count ?? 0} clapped={!!pTally?.mine}
                                  busy={clapBusy.has('performer:' + performer.user_id)}
                                  label={getUserNickname(performer.user_id)}
                                  on:toggle={() => togglePerformerClap(performer.user_id)} />
                {:else if pTally?.count}
                  <ApplauseButton count={pTally.count} readOnly />
                {/if}
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
          {#if confirmDialog.warning}
            <div class="flex items-start gap-2 bg-base-950 rounded-lg p-3">
              <AlertTriangle class="text-yellow shrink-0 mt-0.5" size={18} />
              <div class="flex flex-col gap-2 min-w-0">
                <span class="text-white text-sm">{confirmDialog.warning}</span>
                {#if confirmDialog.people?.length}
                  <div class="flex flex-wrap items-center gap-x-3 gap-y-1.5">
                    {#each confirmDialog.people as p (p.user_id)}
                      <span class="inline-flex items-center gap-1.5 min-w-0">
                        <img src={p.avatar} alt="" class="w-6 h-6 rounded-full border border-cold-base shrink-0" />
                        <span class="text-cold-light text-xs truncate">{p.name}</span>
                      </span>
                    {/each}
                  </div>
                {/if}
              </div>
            </div>
          {/if}
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

<!-- Song detail as an overlay (#94). Rendered over this page rather than
     replacing it, so the page underneath keeps its state and its realtime
     subscription. `page.state.perfId` is set by pushState and cleared by the
     browser going back, which is why the close button just calls history.back()
     — one code path for both the button and the hardware/gesture back.
     Keyed on the id so opening a different song mounts a fresh component
     instead of reusing one whose onMount already ran. -->
<svelte:window on:keydown={overlayKeydown} />

{#if page.state.perfId}
  <div use:lockScroll class="fixed inset-0 z-40 bg-base-950 overflow-y-auto overscroll-contain" role="dialog" aria-modal="true" aria-label="Detalle de la canción">
    <div class="max-w-2xl mx-auto w-full" style="padding-bottom: calc(env(safe-area-inset-bottom, 0px) + 3rem)">
      {#key page.state.perfId}
        <PerformanceDetail performanceId={page.state.perfId} onClose={closeSong} />
      {/key}
    </div>
  </div>
{/if}
