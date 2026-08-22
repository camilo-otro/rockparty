<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft } from 'lucide-svelte';
  import PartyListItem from '$lib/components/PartyListItem.svelte';

  // 'loading' until auth is known, so we don't flash the logged-out gate.
  let authState: 'loading' | 'in' | 'out' = 'loading';
  let parties: any[] = [];
  let venues: Record<number, string> = {};

  const IN_PROGRESS = ['draft', 'pending_venue'];
  const UPCOMING = ['confirmed', 'live'];
  const PAST = ['completed', 'cancelled'];

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { authState = 'out'; return; }
    const uid = session.user.id;

    const { data } = await supabase
      .from('party')
      .select('id, title, description, date, venue, status')
      .eq('created_by', uid);
    parties = data ?? [];

    const venueIds = [...new Set(parties.map((p) => p.venue).filter(Boolean))];
    if (venueIds.length) {
      const { data: vData } = await supabase.from('venue').select('id, name').in('id', venueIds);
      venues = Object.fromEntries((vData ?? []).map((v: any) => [v.id, v.name]));
    }
    authState = 'in';
  });

  const byDateAsc = (a: any, b: any) => new Date(a.date).getTime() - new Date(b.date).getTime();
  const byDateDesc = (a: any, b: any) => new Date(b.date).getTime() - new Date(a.date).getTime();

  // In-progress first (the toques that are otherwise unreachable), then upcoming, then past.
  $: enProceso = parties.filter((p) => IN_PROGRESS.includes(p.status)).sort(byDateAsc);
  $: proximos = parties.filter((p) => UPCOMING.includes(p.status)).sort(byDateAsc);
  $: pasados = parties.filter((p) => PAST.includes(p.status)).sort(byDateDesc);

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
    {:else if parties.length === 0}
      <div class="mx-4 p-6 bg-base-900 text-white rounded-lg text-center flex flex-col gap-3">
        <span>Aún no has organizado ningún toque.</span>
        <a href="/parties/create" class="bg-cold-base text-white rounded-lg px-4 py-2 self-center">Organiza un toque</a>
      </div>
    {:else}
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
  </section>
</div>
