<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronsDown, Plus, AlertTriangle } from 'lucide-svelte';
  import PartyListItem from '$lib/components/PartyListItem.svelte';
  import VenueListItem from '$lib/components/VenueListItem.svelte';
  import { user } from '$lib/stores/user';

  let parties: any[] = [];
  let venues: any[] = [];
  let loading = true;
  let error: string | null = null;
  let topVenues: any[] = [];

  // Role-based sections (#55), derived from actual venue ownership.
  let currentUserId: string | null = null;
  let managedVenueIds: number[] = [];
  let pendingApprovals: any[] = [];
  let venueUpcoming: any[] = [];
  // #36: upcoming toques that need an instrument you play (and you're not in).
  let needsYou: { party: any; needed: string[] }[] = [];
  let hasParticipated = false;
  let authChecked = false;

  const now = new Date();
  const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

  // Generic hero: only for logged-out visitors and logged-in users who haven't
  // participated yet (#64 will make this contextual).
  $: showHero = currentUserId === null || (authChecked && !hasParticipated);

  onMount(async () => {
    user.subscribe((u) => { currentUserId = u?.id ?? null; })();

    // Public discovery data (everyone).
    const { data: partyData, error: partyErr } = await supabase
      .from('party').select('id, title, date, venue, status, is_test')
      .in('status', ['confirmed', 'live']).order('date', { ascending: true });
    const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name, address, is_test');
    if (partyErr || venueErr) {
      error = partyErr?.message ?? venueErr?.message ?? null;
      loading = false;
      return;
    }
    parties = partyData ?? [];
    venues = venueData ?? [];
    const upcomingParties = parties
      .filter((p) => new Date(p.date) >= now)
      .sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());
    const venueCounts: Record<string | number, number> = {};
    for (const party of upcomingParties) venueCounts[party.venue] = (venueCounts[party.venue] || 0) + 1;
    topVenues = venues.map((v) => ({ ...v, count: venueCounts[v.id] || 0 })).sort((a, b) => b.count - a.count).slice(0, 5);
    parties = upcomingParties.slice(0, 5);

    // Venue-manager sections (#55).
    if (currentUserId) {
      const [{ data: owned }, { data: adminOf }] = await Promise.all([
        supabase.from('venue').select('id').eq('created_by', currentUserId),
        supabase.from('venue_admin').select('venue_id').eq('user_id', currentUserId)
      ]);
      managedVenueIds = [...new Set([...(owned ?? []).map((v) => v.id), ...(adminOf ?? []).map((a) => a.venue_id)])];

      if (managedVenueIds.length) {
        const { data: pend } = await supabase
          .from('party').select('id, title, date, venue, status, is_test')
          .eq('status', 'pending_venue').in('venue', managedVenueIds).order('date', { ascending: true });
        pendingApprovals = pend ?? [];
        const { data: vu } = await supabase
          .from('party').select('id, title, date, venue, status, is_test')
          .in('status', ['confirmed', 'live']).in('venue', managedVenueIds).gte('date', todayStr).order('date', { ascending: true });
        venueUpcoming = vu ?? [];
      }

      // #36: match the user's instruments against open slots in upcoming toques.
      const { data: myInstr } = await supabase.from('profile_instrument').select('instrument_id').eq('profile_id', currentUserId);
      const myInstrumentIds = (myInstr ?? []).map((r) => r.instrument_id);
      if (myInstrumentIds.length && upcomingParties.length) {
        const upIds = upcomingParties.map((p) => p.id);
        const { data: perfRows } = await supabase.from('performance').select('id, party').in('party', upIds);
        const perfIds = (perfRows ?? []).map((p) => p.id);
        const { data: appr } = perfIds.length
          ? await supabase.from('performance_user').select('performance_id, instrument_id, user_id').eq('status', 'approved').in('performance_id', perfIds)
          : { data: [] as any[] };
        const { data: instrData } = await supabase.from('instrument').select('id, name');
        const instrName = new Map((instrData ?? []).map((i: any) => [i.id, i.name]));
        const allInstrIds = (instrData ?? []).map((i: any) => i.id);

        const filledByPerf: Record<number, Set<number>> = {};
        const myApprovedParties = new Set<number>();
        const perfsByParty: Record<number, number[]> = {};
        for (const pf of perfRows ?? []) if (pf.party != null) (perfsByParty[pf.party] ??= []).push(pf.id);
        for (const a of appr ?? []) {
          (filledByPerf[a.performance_id] ??= new Set()).add(a.instrument_id);
          if (a.user_id === currentUserId) {
            const pf = (perfRows ?? []).find((p) => p.id === a.performance_id);
            if (pf?.party != null) myApprovedParties.add(pf.party);
          }
        }
        needsYou = upcomingParties
          .filter((p) => !myApprovedParties.has(p.id))
          .map((p) => {
            const open = new Set<number>();
            for (const pid of perfsByParty[p.id] ?? []) {
              const filled = filledByPerf[pid] ?? new Set<number>();
              for (const iid of allInstrIds) if (!filled.has(iid)) open.add(iid);
            }
            const needed = myInstrumentIds.filter((iid) => open.has(iid)).map((iid) => instrName.get(iid)).filter(Boolean) as string[];
            return { party: p, needed };
          })
          .filter((x) => x.needed.length > 0);
      }

      // Has the user participated in any way? (drives the generic hero.)
      const [{ count: myToques }, { count: mySignups }] = await Promise.all([
        supabase.from('party').select('id', { count: 'exact', head: true }).eq('created_by', currentUserId),
        supabase.from('performance_user').select('user_id', { count: 'exact', head: true }).eq('user_id', currentUserId)
      ]);
      hasParticipated = managedVenueIds.length > 0 || (myToques ?? 0) > 0 || (mySignups ?? 0) > 0;
    }
    authChecked = true;
    loading = false;
  });

  function getVenueName(venueId: number) {
    const venue = venues.find((v) => v.id === venueId);
    return venue ? venue.name : 'Sin nombre';
  }
</script>

<div class="mt-8 flex flex-col gap-8">
  {#if showHero}
    <section class="mx-4">
      <div class="bg-base-900 rounded-lg p-6 text-center">
        <p class="text-white text-lg leading-snug">
          Conéctate con <span class="font-bold">músicos</span>, encuentra <span class="font-bold">locales</span> y lleva tu música al <span class="font-bold">siguiente nivel</span>.
        </p>
        <a href="/como-funciona" class="text-cold-light inline-block mt-3 hover:underline">Aprende cómo funciona</a>
      </div>
    </section>
  {/if}

  {#if pendingApprovals.length}
    <section>
      <h2 class="text-3xl text-white m-4 mb-4 flex items-center gap-2">
        <AlertTriangle class="text-yellow" size={28} /> POR APROBAR · {pendingApprovals.length}
      </h2>
      <div class="m-4 mt-0 rounded-lg overflow-clip">
        <ul class="p-0 space-y-[1px]">
          {#each pendingApprovals as party}
            <PartyListItem {party} venueName={getVenueName(party.venue)} showStatus />
          {/each}
        </ul>
      </div>
    </section>
  {/if}

  {#if venueUpcoming.length}
    <section>
      <h2 class="text-3xl text-white m-4 mb-4">TUS LOCALES</h2>
      <div class="m-4 mt-0 rounded-lg overflow-clip">
        <ul class="p-0 space-y-[1px]">
          {#each venueUpcoming as party}
            <PartyListItem {party} venueName={getVenueName(party.venue)} showStatus />
          {/each}
        </ul>
      </div>
    </section>
  {/if}

  {#if needsYou.length}
    <section>
      <h2 class="text-3xl text-white m-4 mb-1">TE NECESITAN</h2>
      <p class="text-cold-light text-sm mx-4 mb-4">Toques con un cupo abierto en lo que tocas.</p>
      <div class="m-4 mt-0 rounded-lg overflow-clip">
        <ul class="p-0 space-y-[1px]">
          {#each needsYou as m}
            <PartyListItem party={m.party} venueName={getVenueName(m.party.venue)} noteBadge={{ text: m.needed.join(' · '), cls: 'bg-cold-base text-white' }} />
          {/each}
        </ul>
      </div>
    </section>
  {/if}

  <section>
    <h2 class="text-3xl text-white m-4 mb-4">PRÓXIMOS TOQUES</h2>
    <div class="m-4 rounded-lg overflow-clip flex flex-col">
      <a href="/parties/create" class="w-full bg-cold-base text-white text-sm block text-center p-2">Planea un nuevo toque <Plus class="inline-block" /></a>
      {#if loading}
        <div>Cargando...</div>
      {:else if error}
        <div class="text-red-500">Error: {error}</div>
      {:else if parties.length === 0}
        <div>No hay próximos toques registrados.</div>
      {:else}
        <ul class="p-0 space-y-[1px]">
          {#each parties as party}
            <PartyListItem party={party} venueName={getVenueName(party.venue)} />
          {/each}
          <li class="bg-base-900 flex flex-row w-full">
            <a href="/parties" class="text-cold-light px-4 p-2 mx-auto">Ver más toques <ChevronsDown class="inline-block" /></a>
          </li>
        </ul>
      {/if}
    </div>
  </section>

  <section>
    <h2 class="text-3xl m-4 mb-4">LOCALES CERCANOS</h2>
    <div class="m-4 rounded-lg overflow-clip flex flex-col">
      {#if loading}
        <div>Cargando...</div>
      {:else if error}
        <div class="text-red-500">Error: {error}</div>
      {:else if topVenues.length === 0}
        <div>No hay locales con fiestas próximas.</div>
      {:else}
        <ul class="p-0 space-y-[1px]">
          {#each topVenues as venue}
            <VenueListItem venue={venue} />
          {/each}
          <li class="bg-base-900 flex flex-row w-full">
            <a href="/venues" class="text-cold-light px-4 p-2 mx-auto">Ver más locales<ChevronsDown class="inline-block" /></a>
          </li>
        </ul>
      {/if}
    </div>
  </section>
</div>
