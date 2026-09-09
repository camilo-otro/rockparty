<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { Minus, Plus, Check, ArrowRight } from 'lucide-svelte';
  import { reportError, toastSuccess } from '$lib/stores/toasts';

  // Logistics quick-start (#97). The list #95 built starts EMPTY, which is why
  // nobody fills it in: eight or nine taps before it reflects a normal rock gig.
  // This offers the standard set in one pass, right after a toque is created.
  //
  // A step AFTER the insert, not a wizard inside PartyForm: that component is
  // shared with edit, requirements need a party_id that does not exist until the
  // insert, and creating a toque is the funnel's most important action — here the
  // toque already exists, so "Saltar" can never cost anything.
  const partyId = Number(page.params.id);

  type Row = {
    key: string;
    kind: 'equipment' | 'role';
    itemId: number;
    name: string;
    category: string | null;
    on: boolean;
    quantity: number;
    fromVenue: boolean;
    venueNotes: string | null;
  };

  let rows: Row[] = [];
  let party: any = null;
  let loading = true;
  let saving = false;
  let denied = false;

  onMount(async () => {
    // A non-numeric id makes partyId NaN, which PostgREST answers with 400s.
    // The page still degrades to `denied`, but bail first so three failed
    // requests do not sit in the console masking real errors later.
    if (!Number.isFinite(partyId)) { denied = true; loading = false; return; }
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { denied = true; loading = false; return; }

    const [partyRes, adminRes, eqRes, roleRes, existingRes] = await Promise.all([
      supabase.from('party').select('id, title, venue, created_by').eq('id', partyId).maybeSingle(),
      supabase.from('party_admin').select('user_id').eq('party_id', partyId),
      supabase.from('equipment').select('id, name, category, is_basic, default_quantity').eq('is_basic', true).order('id'),
      supabase.from('party_role').select('id, name, is_basic').eq('is_basic', true).order('id'),
      // Idempotency: the step normally runs on an empty list, but a back-button
      // must not be able to duplicate. Same rule seedFromVenue uses.
      supabase.from('party_requirement').select('equipment_id, role_id').eq('party_id', partyId)
    ]);

    party = partyRes.data;
    // Creator OR party_admin — the same notion is_party_admin() uses in RLS.
    // Matching it matters: a co-organizer's write would SUCCEED at the database,
    // so gating on creator alone would refuse a screen that actually works.
    const admins = (adminRes.data ?? []).map((a: any) => a.user_id);
    const mayEdit = !!party && (party.created_by === session.user.id || admins.includes(session.user.id));
    if (!mayEdit) { denied = true; loading = false; return; }

    const { data: ve } = party.venue
      ? await supabase.from('venue_equipment').select('equipment_id, quantity, notes').eq('venue_id', party.venue)
      : { data: [] as any[] };
    const venueBy = new Map((ve ?? []).map((v: any) => [v.equipment_id, v]));

    const takenEquipment = new Set((existingRes.data ?? []).map((r: any) => r.equipment_id).filter(Boolean));
    const takenRoles = new Set((existingRes.data ?? []).map((r: any) => r.role_id).filter(Boolean));

    rows = [
      ...(eqRes.data ?? [])
        .filter((e: any) => !takenEquipment.has(e.id))
        .map((e: any) => {
          const v: any = venueBy.get(e.id);
          return {
            key: `e${e.id}`,
            kind: 'equipment' as const,
            itemId: e.id,
            name: e.name,
            category: e.category,
            // Defaults ON: a rock gig needs a PA, mics, drums and amps, and
            // defaulting off would make this screen a no-op for anyone who just
            // taps Listo.
            on: true,
            quantity: v?.quantity ?? e.default_quantity ?? 1,
            fromVenue: !!v,
            venueNotes: v?.notes ?? null
          };
        }),
      ...(roleRes.data ?? [])
        .filter((r: any) => !takenRoles.has(r.id))
        // No quantity on a role — quantity_is_equipment_only forbids it, so no
        // stepper is rendered for these.
        .map((r: any) => ({
          key: `r${r.id}`, kind: 'role' as const, itemId: r.id, name: r.name,
          category: null, on: true, quantity: 1, fromVenue: false, venueNotes: null
        }))
    ];
    loading = false;
  });

  $: chosen = rows.filter((r) => r.on);
  $: fromVenueCount = chosen.filter((r) => r.fromVenue).length;
  // What the organizer will have to chase. Per the spec this is the DELIVERABLE,
  // not a shortfall — so it is stated plainly rather than softened.
  $: gapCount = chosen.length - fromVenueCount;

  function toggle(key: string) {
    rows = rows.map((r) => (r.key === key ? { ...r, on: !r.on } : r));
  }
  function bump(key: string, by: number) {
    rows = rows.map((r) => (r.key === key ? { ...r, quantity: Math.max(1, r.quantity + by) } : r));
  }

  async function save() {
    if (saving) return;
    if (!chosen.length) { goto(`/parties/${partyId}`); return; }
    saving = true;
    const now = new Date().toISOString();
    // One bulk insert, not one per row (#84).
    const payload = chosen.map((r) => ({
      party_id: partyId,
      kind: r.kind,
      equipment_id: r.kind === 'equipment' ? r.itemId : null,
      role_id: r.kind === 'role' ? r.itemId : null,
      quantity: r.kind === 'equipment' ? r.quantity : null,
      // The venue's profile already declares its gear, so those arrive resolved
      // and pre-confirmed; everything else is a gap by definition.
      source: r.fromVenue ? ('venue' as const) : ('unassigned' as const),
      confirmed_at: r.fromVenue ? now : null,
      notes: r.venueNotes
    }));
    const { error } = await supabase.from('party_requirement').insert(payload as any);
    saving = false;
    if (error) { reportError(error); return; }
    toastSuccess(`Listo — ${payload.length} ${payload.length === 1 ? 'cosa' : 'cosas'} en la lista.`);
    goto(`/parties/${partyId}`);
  }
</script>

<svelte:head><title>¿Qué necesitas? · Rock the House</title></svelte:head>

<div class="p-4 max-w-md mx-auto">
  {#if loading}
    <div class="mt-8 p-6 bg-base-900 text-white rounded-lg text-center">Cargando…</div>

  {:else if denied}
    <div class="mt-8 p-6 bg-base-900 text-white rounded-lg text-center flex flex-col gap-3">
      <span>No puedes preparar la logística de este toque.</span>
      <a href="/parties" class="text-cold-light underline">Ver los toques</a>
    </div>

  {:else}
    <div class="mt-6 flex flex-col gap-4">
      <div>
        <h1 class="text-3xl text-yellow leading-tight">¿Qué necesitas?</h1>
        <p class="text-cold-light text-sm mt-1">
          Esto es lo típico de un toque. Apaga lo que no te haga falta — puedes cambiarlo después.
        </p>
      </div>

      <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip p-0">
        {#each rows as r (r.key)}
          <li class="bg-base-900 px-3 py-3 flex items-center gap-3">
            <button
              type="button"
              role="switch"
              aria-checked={r.on}
              aria-label="{r.name}"
              on:click={() => toggle(r.key)}
              class="shrink-0"
            >
              <span class="w-9 h-5 rounded-full block relative transition-colors {r.on ? 'bg-cold-base' : 'bg-base-950'}">
                <span class="absolute top-0.5 w-4 h-4 rounded-full bg-white transition-all {r.on ? 'left-[1.125rem]' : 'left-0.5'}"></span>
              </span>
            </button>

            <div class="grow min-w-0">
              <div class="{r.on ? 'text-white' : 'text-cold-light/50'}">
                {r.name}
                {#if r.kind === 'role'}
                  <span class="text-[0.6rem] uppercase tracking-wide px-1.5 py-0.5 ml-1 rounded-full border border-cold-light/40 text-cold-light whitespace-nowrap">Rol</span>
                {/if}
                {#if r.fromVenue}
                  <span class="text-[0.6rem] uppercase tracking-wide px-1.5 py-0.5 ml-1 rounded-full border border-green-500/60 text-green-500 whitespace-nowrap">Del local</span>
                {/if}
              </div>
              {#if r.venueNotes}<div class="text-xs text-cold-light truncate">{r.venueNotes}</div>{/if}
            </div>

            <!-- Equipment only. A role cannot carry a quantity — the
                 quantity_is_equipment_only constraint refuses it at the DB. -->
            {#if r.on && r.kind === 'equipment'}
              <div class="flex items-center gap-1 shrink-0">
                <button type="button" on:click={() => bump(r.key, -1)} disabled={r.quantity <= 1}
                  aria-label="Menos {r.name}"
                  class="w-7 h-7 rounded-full border border-cold-light/40 text-cold-light inline-flex items-center justify-center disabled:opacity-30"><Minus size={14} /></button>
                <span class="text-white w-5 text-center tabular-nums">{r.quantity}</span>
                <button type="button" on:click={() => bump(r.key, 1)}
                  aria-label="Más {r.name}"
                  class="w-7 h-7 rounded-full border border-cold-light/40 text-cold-light inline-flex items-center justify-center"><Plus size={14} /></button>
              </div>
            {/if}
          </li>
        {/each}
      </ul>

      {#if chosen.length}
        <p class="text-cold-light text-sm">
          {#if fromVenueCount}
            El local pone {fromVenueCount}.
          {/if}
          {#if gapCount === 1}
            Te queda <span class="text-warm-base">1</span> por conseguir — lo marcamos para que no se te pase.
          {:else if gapCount}
            Te quedan <span class="text-warm-base">{gapCount}</span> por conseguir — los marcamos para que no se te pasen.
          {:else}
            Con eso está todo cubierto.
          {/if}
        </p>
      {/if}

      <div class="flex flex-col gap-2">
        <button type="button" on:click={save} disabled={saving}
          class="bg-cold-base text-white rounded-lg px-4 py-3 inline-flex items-center justify-center gap-2 disabled:opacity-60">
          <Check size={18} /> {saving ? 'Guardando…' : chosen.length ? `Listo · ${chosen.length}` : 'Listo'}
        </button>
        <!-- As prominent as Listo: the toque already exists, so nobody should
             feel trapped on this screen. -->
        <a href={`/parties/${partyId}`} class="text-cold-light text-center px-4 py-2 inline-flex items-center justify-center gap-1">
          Saltar por ahora <ArrowRight size={15} />
        </a>
      </div>
    </div>
  {/if}
</div>
