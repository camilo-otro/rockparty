<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, Plus, AlertTriangle } from 'lucide-svelte';
  import VenueListItem from '$lib/components/VenueListItem.svelte';
  import { showTest, keepTest } from '$lib/stores/showTest';

  // "Mis locales" — the venue-manager counterpart to /parties/mine.
  let authState: 'loading' | 'in' | 'out' = 'loading';
  let venues: any[] = [];
  let pendingByVenue: Record<number, number> = {};

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { authState = 'out'; return; }
    const uid = session.user.id;

    // Both halves in one wave. Unlike parties and bands, nothing adds a venue's
    // creator to venue_admin, so ownership and admin membership are genuinely
    // separate questions — the same pair the home page and the menu store ask.
    const [ownedRes, adminRes] = await Promise.all([
      supabase.from('venue').select('id, name, address, is_test').eq('created_by', uid),
      supabase.from('venue_admin').select('venue_id').eq('user_id', uid)
    ]);

    const owned = ownedRes.data ?? [];
    const adminIds = (adminRes.data ?? [])
      .map((a: any) => a.venue_id)
      .filter((id: number) => !owned.some((v: any) => v.id === id));

    const { data: adminVenues } = adminIds.length
      ? await supabase.from('venue').select('id, name, address, is_test').in('id', adminIds)
      : { data: [] as any[] };

    venues = [...owned, ...(adminVenues ?? [])].sort((a, b) =>
      (a.name ?? '').localeCompare(b.name ?? '')
    );

    // The one thing a venue manager actually has to ACT on: toques waiting for
    // their approval. Same predicate the home page's "POR APROBAR" uses.
    const ids = venues.map((v) => v.id);
    if (ids.length) {
      const { data: pend } = await supabase
        .from('party').select('venue').eq('status', 'pending_venue').in('venue', ids);
      const tally: Record<number, number> = {};
      for (const p of pend ?? []) if (p.venue != null) tally[p.venue] = (tally[p.venue] ?? 0) + 1;
      pendingByVenue = tally;
    }
    authState = 'in';
  });

  // $showTest named textually — legacy mode tracks `$:` deps by name.
  $: visible = keepTest(venues, $showTest);
  $: pendingTotal = visible.reduce((n, v) => n + (pendingByVenue[v.id] ?? 0), 0);
</script>

<div class="flex flex-col items-left">
  <div class="flex flex-row items-center">
    <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft />VOLVER</a>
  </div>

  <section>
    <div class="flex items-center justify-between mx-4 mb-4">
      <h2 class="text-3xl text-white">MIS LOCALES</h2>
      {#if pendingTotal}
        <span class="inline-flex items-center gap-1 text-xs uppercase tracking-wide px-2 py-1 rounded-full bg-yellow text-black">
          <AlertTriangle size={13} /> {pendingTotal} por aprobar
        </span>
      {/if}
    </div>

    {#if authState === 'loading'}
      <div class="text-white p-4 mx-4">Cargando...</div>

    {:else if authState === 'out'}
      <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
        Debes iniciar sesión para ver tus locales.
      </div>

    {:else if !visible.length}
      <div class="mx-4 p-6 bg-base-900 text-white rounded-lg text-center flex flex-col gap-3">
        <span>Aún no administras ningún local.</span>
        <a href="/venues/create" class="bg-cold-base text-white rounded-lg px-4 py-2 self-center">Agregar un local</a>
      </div>

    {:else}
      <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
        {#each visible as venue (venue.id)}
          <VenueListItem {venue} />
          {#if pendingByVenue[venue.id]}
            <!-- The actionable bit, right under the venue it belongs to. -->
            <li class="bg-base-900 px-4 pb-3 -mt-[1px]">
              <a href="/" class="text-yellow text-sm inline-flex items-center gap-1">
                <AlertTriangle size={14} />
                {pendingByVenue[venue.id]}
                {pendingByVenue[venue.id] === 1 ? 'toque espera' : 'toques esperan'} tu aprobación
              </a>
            </li>
          {/if}
        {/each}
      </ul>

      <div class="flex justify-center p-4">
        <a class="bg-cold-base text-white rounded-lg px-6 py-3 inline-flex items-center gap-2" href="/venues/create">
          <Plus size={18} /> Agregar un local
        </a>
      </div>
    {/if}
  </section>
</div>
