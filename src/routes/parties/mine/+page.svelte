<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft } from 'lucide-svelte';
  import PartyListItem from '$lib/components/PartyListItem.svelte';
  import { showTest, keepTest } from '$lib/stores/showTest';

  // 'loading' until auth is known, so we don't flash the logged-out gate.
  let authState: 'loading' | 'in' | 'out' = 'loading';
  let parties: any[] = [];
  // Toques the user plays in (has a signup) but does NOT organize (#29).
  let playParties: any[] = [];
  let signupBadgeByParty: Record<number, { text: string; cls: string }> = {};
  // Toques the user is attending via RSVP (#58), not organizing.
  let asistoParties: any[] = [];
  let venues: Record<number, string> = {};

  const IN_PROGRESS = ['draft', 'pending_venue'];

  // Local YYYY-MM-DD (never toISOString — that's UTC and can shift the day).
  const _now = new Date();
  const todayStr = `${_now.getFullYear()}-${String(_now.getMonth() + 1).padStart(2, '0')}-${String(_now.getDate()).padStart(2, '0')}`;

  // Past/upcoming is decided by the DATE, not the status. It used to be purely
  // status-driven (UPCOMING = confirmed|live, PAST = completed|cancelled), which
  // was wrong in both directions: nothing ever sets `completed`, so a toque from
  // last year sat under PRÓXIMOS forever, while a toque cancelled months ahead of
  // time showed under PASADOS.
  //
  // `completed` still forces past regardless of date — that status is set by
  // running a show to the end, and its date is typically today.
  const isInProgress = (p: any) => IN_PROGRESS.includes(p.status);
  const isPast = (p: any) => p.status === 'completed' || String(p.date) < todayStr;

  // One badge per toque, by precedence: playing (approved) > pending > declined.
  function signupBadge(statuses: Set<string>): { text: string; cls: string } {
    if (statuses.has('approved')) return { text: 'Tocas', cls: 'bg-cold-base text-white' };
    if (statuses.has('pending')) return { text: 'Pendiente', cls: 'bg-yellow text-black' };
    return { text: 'Rechazado', cls: 'bg-warm-base text-white' };
  }

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { authState = 'out'; return; }
    const uid = session.user.id;

    // Wave 1: all three of these need only the user id (#86, see #84). They were
    // running in series, which cost two round trips for nothing.
    const PARTY_COLS = 'id, title, description, date, venue, status, is_test';
    const [organizedRes, myRowsRes, rsvpRes] = await Promise.all([
      supabase.from('party').select(PARTY_COLS).eq('created_by', uid),
      supabase.from('performance_user').select('performance_id, status').eq('user_id', uid),
      supabase.from('party_rsvp').select('party_id').eq('user_id', uid)
    ]);
    parties = organizedRes.data ?? [];
    const organizedIds = new Set(parties.map((p) => p.id));
    const myRows = myRowsRes.data;
    const rsvpRows = rsvpRes.data;

    // Wave 2: the RSVP'd toques need only ids we now have, so they go in flight
    // alongside the performance lookup rather than after the whole playing chain.
    const rsvpIds = [...new Set((rsvpRows ?? []).map((r) => r.party_id))].filter((id) => !organizedIds.has(id));
    const perfIds = [...new Set((myRows ?? []).map((r) => r.performance_id))];
    const [perfRowsRes, asistoRes] = await Promise.all([
      perfIds.length
        ? supabase.from('performance').select('id, party').in('id', perfIds)
        : Promise.resolve({ data: [] as any[] }),
      rsvpIds.length
        ? supabase.from('party').select(PARTY_COLS).in('id', rsvpIds)
        : Promise.resolve({ data: [] as any[] })
    ]);
    asistoParties = asistoRes.data ?? [];

    if (perfIds.length) {
      const perfRows = perfRowsRes.data;
      const partyByPerf = Object.fromEntries((perfRows ?? []).map((p: any) => [p.id, p.party]));
      const statusByParty: Record<number, Set<string>> = {};
      for (const r of myRows ?? []) {
        const pid = partyByPerf[r.performance_id];
        if (pid == null || organizedIds.has(pid)) continue; // skip toques you organize
        (statusByParty[pid] ??= new Set()).add(r.status);
      }
      const playIds = Object.keys(statusByParty).map(Number);
      if (playIds.length) {
        // Genuinely a further hop: needs the performance -> party mapping above.
        const { data: pData } = await supabase.from('party').select(PARTY_COLS).in('id', playIds);
        playParties = pData ?? [];
        signupBadgeByParty = Object.fromEntries(playIds.map((id) => [id, signupBadge(statusByParty[id])]));
      }
    }

    const venueIds = [...new Set([...parties, ...playParties, ...asistoParties].map((p) => p.venue).filter(Boolean))];
    if (venueIds.length) {
      const { data: vData } = await supabase.from('venue').select('id, name').in('id', venueIds);
      venues = Object.fromEntries((vData ?? []).map((v: any) => [v.id, v.name]));
    }
    authState = 'in';
  });

  const byDateAsc = (a: any, b: any) => new Date(a.date).getTime() - new Date(b.date).getTime();
  const byDateDesc = (a: any, b: any) => new Date(b.date).getTime() - new Date(a.date).getTime();

  // `$showTest` is named in each expression on purpose — Svelte legacy mode
  // tracks dependencies textually, so hiding the store read inside keepTest()
  // alone would leave these stale when the switch is flipped.
  $: misToques = keepTest(parties, $showTest);
  $: misToco = keepTest(playParties, $showTest);
  $: misAsisto = keepTest(asistoParties, $showTest);

  // In-progress first (the toques that are otherwise unreachable), then upcoming, then past.
  $: enProceso = misToques.filter(isInProgress).sort(byDateAsc);
  $: proximos = misToques.filter((p) => !isInProgress(p) && !isPast(p)).sort(byDateAsc);
  $: pasados = misToques.filter((p) => !isInProgress(p) && isPast(p)).sort(byDateDesc);
  // "Toco" toques: upcoming first, then past (drafts you can't see aren't here).
  $: tocoProximos = misToco.filter((p) => !isPast(p)).sort(byDateAsc);
  $: tocoPasados = misToco.filter((p) => isPast(p)).sort(byDateDesc);
  // "Asisto" toques (RSVP): upcoming first, then past.
  $: asistoProximos = misAsisto.filter((p) => !isPast(p)).sort(byDateAsc);
  $: asistoPasados = misAsisto.filter((p) => isPast(p)).sort(byDateDesc);
  $: hasOrganizo = misToques.length > 0;
  $: hasToco = misToco.length > 0;
  $: hasAsisto = misAsisto.length > 0;

  function venueName(id: number) {
    return venues[id] ?? 'Sin local';
  }
</script>

<div class="flex flex-col items-left">
  <div class="flex flex-row items-center">
    <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft />VOLVER</a>
  </div>
  <section>
    <h2 class="text-3xl text-white m-4 mb-4">MIS TOQUES</h2>

    {#if authState === 'loading'}
      <div class="text-white p-4 mx-4">Cargando...</div>
    {:else if authState === 'out'}
      <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
        Debes iniciar sesión para ver tus toques.
      </div>
    {:else if !hasOrganizo && !hasToco && !hasAsisto}
      <div class="mx-4 p-6 bg-base-900 text-white rounded-lg text-center flex flex-col gap-3">
        <span>Aún no organizas, tocas ni asistes a ningún toque.</span>
        <a href="/parties/create" class="bg-cold-base text-white rounded-lg px-4 py-2 self-center">Organiza un toque</a>
      </div>
    {:else}
      {#if hasOrganizo}
        <h2 class="text-2xl text-cold-light mx-4 mb-3 tracking-widest">ORGANIZO</h2>
        {#if enProceso.length}
          <h3 class="text-xl text-yellow mx-4 mb-2">EN PROCESO</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each enProceso as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus />
            {/each}
          </ul>
        {/if}
        {#if proximos.length}
          <h3 class="text-xl text-white mx-4 mb-2">PRÓXIMOS</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each proximos as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus />
            {/each}
          </ul>
        {/if}
        {#if pasados.length}
          <h3 class="text-xl text-white mx-4 mb-2">PASADOS</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each pasados as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus />
            {/each}
          </ul>
        {/if}
      {/if}

      {#if hasToco}
        <h2 class="text-2xl text-cold-light mx-4 mb-3 mt-6 tracking-widest">TOCO</h2>
        {#if tocoProximos.length}
          <h3 class="text-xl text-white mx-4 mb-2">PRÓXIMOS</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each tocoProximos as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus noteBadge={signupBadgeByParty[party.id]} />
            {/each}
          </ul>
        {/if}
        {#if tocoPasados.length}
          <h3 class="text-xl text-white mx-4 mb-2">PASADOS</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each tocoPasados as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus noteBadge={signupBadgeByParty[party.id]} />
            {/each}
          </ul>
        {/if}
      {/if}

      {#if hasAsisto}
        <h2 class="text-2xl text-cold-light mx-4 mb-3 mt-6 tracking-widest">ASISTO</h2>
        {#if asistoProximos.length}
          <h3 class="text-xl text-white mx-4 mb-2">PRÓXIMOS</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each asistoProximos as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus />
            {/each}
          </ul>
        {/if}
        {#if asistoPasados.length}
          <h3 class="text-xl text-white mx-4 mb-2">PASADOS</h3>
          <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
            {#each asistoPasados as party}
              <PartyListItem {party} venueName={venueName(party.venue)} showStatus />
            {/each}
          </ul>
        {/if}
      {/if}
    {/if}
  </section>
</div>
