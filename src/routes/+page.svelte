<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronsDown, Plus, AlertTriangle, Guitar, Mic, CalendarPlus, Sparkles, ArrowRight } from 'lucide-svelte';
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
  let authChecked = false;

  const now = new Date();
  const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;

  // Contextual home hero (#64): one priority-picked card nudging the next step in
  // the participation funnel (set instruments → play → organize), or the generic
  // value-prop for logged-out / brand-new users.
  let heroVariant: 'generic' | 'instruments' | 'play' | 'organize' | 'none' = 'none';
  const HERO = {
    generic:     { icon: Sparkles,     title: 'Rock the House',           body: 'Conéctate con músicos, encuentra locales y lleva tu música al siguiente nivel.', cta: 'Aprende cómo funciona',   href: () => '/como-funciona' },
    instruments: { icon: Guitar,       title: '¿Qué instrumentos tocas?', body: 'Cuéntanos lo tuyo y te avisamos cuando un toque necesite lo que tú tocas.',      cta: 'Agrega tus instrumentos', href: () => `/performers/${currentUserId}/edit` },
    play:        { icon: Mic,          title: 'Súmate a un setlist',      body: 'Hay toques armándose. Encuentra uno y pide tu cupo en lo que tocas.',            cta: 'Explora los toques',      href: () => '/parties' },
    organize:    { icon: CalendarPlus, title: 'Arma tu propio toque',     body: 'Ya te subiste a una tarima — ahora organiza tu propia noche.',                   cta: 'Planea un toque',         href: () => '/parties/create' }
  } as const;
  $: hero = heroVariant === 'none' ? null : HERO[heroVariant];

  onMount(async () => {
    user.subscribe((u) => { currentUserId = u?.id ?? null; })();
    // Logged-out visitors get the generic hero immediately; logged-in users get a
    // contextual one once their participation signals resolve (below).
    if (!currentUserId) heroVariant = 'generic';

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

      // Participation signals that drive the contextual hero (#64).
      const [{ count: myToques }, { count: mySignups }, { count: myRsvps }] = await Promise.all([
        supabase.from('party').select('id', { count: 'exact', head: true }).eq('created_by', currentUserId),
        supabase.from('performance_user').select('user_id', { count: 'exact', head: true }).eq('user_id', currentUserId),
        supabase.from('party_rsvp').select('user_id', { count: 'exact', head: true }).eq('user_id', currentUserId)
      ]);
      const hasInstruments = myInstrumentIds.length > 0;
      const hasPlayed = (mySignups ?? 0) > 0;
      const hasOrganized = (myToques ?? 0) > 0;
      const managesVenue = managedVenueIds.length > 0;
      const hasAttended = (myRsvps ?? 0) > 0;
      // Priority: brand-new → generic; plays but no profile instruments → set them;
      // attendee/ready musician with no live matches → invite to play; player who
      // hasn't organized → invite to organize; otherwise no hero (fully engaged /
      // pure venue manager, who has their own sections above).
      if (!hasInstruments && !hasPlayed && !hasOrganized && !managesVenue && !hasAttended) heroVariant = 'generic';
      else if (hasPlayed && !hasInstruments) heroVariant = 'instruments';
      else if (!hasPlayed && (hasAttended || hasInstruments) && needsYou.length === 0) heroVariant = 'play';
      else if (hasPlayed && !hasOrganized && !managesVenue) heroVariant = 'organize';
      else heroVariant = 'none';
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
  {#if hero}
    <section class="mx-4">
      <div class="bg-base-900 rounded-lg overflow-hidden">
        <!-- Brand-gradient accent marks the hero slot (used sparingly). -->
        <div class="h-1" style="background:linear-gradient(90deg,#6C04FF,#71118E,#FF4000)"></div>
        <div class="p-6 flex flex-col items-center text-center gap-3">
          <div class="bg-base-950 rounded-full p-3">
            <svelte:component this={hero.icon} class="text-cold-light" size={26} />
          </div>
          <div>
            <h2 class="text-white text-xl">{hero.title}</h2>
            <p class="text-cold-light text-sm mt-1 leading-snug">{hero.body}</p>
          </div>
          <a href={hero.href()} class="bg-cold-base hover:bg-cold-light hover:text-black text-white rounded-full px-6 py-2 text-sm inline-flex items-center gap-2 transition">
            {hero.cta} <ArrowRight size={16} />
          </a>
        </div>
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
