<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { ChevronLeft, Crown, Edit, Users, CalendarClock } from 'lucide-svelte';

  const bandId = Number(page.params.id);
  let currentUserId: string | null = null;
  let loading = true;
  let band: any = null;
  let members: { user_id: string; nickname: string; role: string; instruments: string[] }[] = [];
  let pendingMembers: { display_name: string; instruments: string[] }[] = []; // #78
  let isManager = false;
  // Toques the band plays / has played (#72) — from performance.band_id -> party.
  let upcomingToques: any[] = [];
  let pastToques: any[] = [];
  let unsub: () => void;

  // Local YYYY-MM-DD (not toISOString — avoids the UTC day-shift).
  function todayStr(): string {
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  onMount(async () => {
    unsub = user.subscribe((u) => { currentUserId = u?.id ?? null; });
    const [{ data: b }, { data: mem }, { data: bmi }, { data: instr }, { data: perfRows }, { data: pend }] = await Promise.all([
      supabase.from('band').select('id, name, bio, is_test, avatar_url').eq('id', bandId).maybeSingle(),
      supabase.from('band_member').select('user_id, role, profile ( nickname )').eq('band_id', bandId),
      supabase.from('band_member_instrument').select('user_id, instrument_id').eq('band_id', bandId),
      supabase.from('instrument').select('id, name'),
      // RLS scopes these to parties the viewer can see; one row per song, dedup below.
      supabase.from('performance').select('party ( id, title, date, status )').eq('band_id', bandId),
      supabase.from('band_pending_member').select('id, display_name, instrument_ids').eq('band_id', bandId) // #78
    ]);
    band = b;
    if (band) {
      // Dedup toques by party (a band can own several songs in one toque), drop
      // cancelled, split upcoming vs past by date.
      const byParty = new Map<number, any>();
      for (const r of perfRows ?? []) {
        const pt = (r as any).party;
        if (pt && pt.status !== 'cancelled' && !byParty.has(pt.id)) byParty.set(pt.id, pt);
      }
      const today = todayStr();
      const all = [...byParty.values()];
      upcomingToques = all.filter((p) => (p.date ?? '') >= today).sort((a, b) => (a.date ?? '').localeCompare(b.date ?? ''));
      pastToques = all.filter((p) => (p.date ?? '') < today).sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''));
      const iName = new Map((instr ?? []).map((i: any) => [i.id, i.name]));
      const instByUser: Record<string, string[]> = {};
      for (const r of bmi ?? []) (instByUser[r.user_id] ??= []).push(iName.get(r.instrument_id));
      members = (mem ?? [])
        .map((m: any) => ({ user_id: m.user_id, nickname: m.profile?.nickname ?? '—', role: m.role, instruments: (instByUser[m.user_id] ?? []).filter(Boolean) }))
        .sort((a, b) => (a.role === b.role ? 0 : a.role === 'manager' ? -1 : 1));
      pendingMembers = (pend ?? []).map((p: any) => ({
        display_name: p.display_name,
        instruments: (p.instrument_ids ?? []).map((id: number) => iName.get(id)).filter(Boolean)
      }));
      isManager = !!currentUserId && members.some((m) => m.user_id === currentUserId && m.role === 'manager');
    }
    loading = false;
  });
  onDestroy(() => unsub?.());
</script>

<div class="max-w-2xl mx-auto p-4 flex flex-col gap-4">
  <div class="flex flex-row justify-between items-center">
    <a href="/bands" class="text-cold-light hover:text-white flex flex-row gap-1"><ChevronLeft /> BANDAS</a>
    {#if isManager}
      <a href={`/bands/${bandId}/edit`} class="bg-cold-light text-black rounded-lg px-4 py-2 inline-flex items-center gap-2 text-sm"><Edit size={16} /> Editar</a>
    {/if}
  </div>

  {#if loading}
    <div class="text-white p-4">Cargando…</div>
  {:else if !band}
    <div class="bg-base-900 rounded-lg p-8 text-center text-white">Esta banda no existe.</div>
  {:else}
    <div class="flex items-center gap-3">
      {#if band.avatar_url}
        <img src={band.avatar_url} alt={band.name} class="w-16 h-16 rounded-full object-cover border border-cold-base bg-base-900" />
      {:else}
        <div class="bg-base-900 rounded-full p-3"><Users class="text-cold-light" size={28} /></div>
      {/if}
      <div class="flex flex-col gap-1">
        <h1 class="text-4xl text-yellow font-medium leading-none">{band.name}</h1>
        {#if band.is_test}<span class="self-start text-[0.65rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-warm-base text-warm-base">Datos de prueba</span>{/if}
      </div>
    </div>
    {#if band.bio}<p class="text-white/90 leading-snug">{band.bio}</p>{/if}

    <h2 class="text-xl text-white mt-2">INTEGRANTES · {members.length + pendingMembers.length}</h2>
    <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
      {#each members as m}
        <li><a href={`/performers/${m.user_id}`} class="bg-base-900 px-4 py-3 flex items-center justify-between gap-3 hover:bg-base-950 transition">
          <div>
            <div class="text-white flex items-center gap-2">
              {m.nickname}
              {#if m.role === 'manager'}<Crown size={13} class="text-yellow" />{/if}
            </div>
            {#if m.instruments.length}<div class="text-sm text-cold-light">{m.instruments.join(' · ')}</div>{/if}
          </div>
        </a></li>
      {/each}
      {#each pendingMembers as p}
        <li class="bg-base-900 px-4 py-3 flex items-center justify-between gap-3">
          <div>
            <div class="text-white/90 flex items-center gap-2">
              {p.display_name}
              <span class="text-[0.6rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-cold-light/40 text-cold-light">Invitado</span>
            </div>
            {#if p.instruments.length}<div class="text-sm text-cold-light">{p.instruments.join(' · ')}</div>{/if}
          </div>
        </li>
      {/each}
    </ul>

    {#if upcomingToques.length || pastToques.length}
      <h2 class="text-xl text-white mt-4 flex items-center gap-2"><CalendarClock size={18} class="text-cold-light" /> TOQUES</h2>
      {#if upcomingToques.length}
        <div class="text-cold-light text-sm -mb-1">Próximos</div>
        <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
          {#each upcomingToques as t}
            <li><a href={`/parties/${t.id}`} class="bg-base-900 px-4 py-3 flex items-center justify-between gap-3 hover:bg-base-950 transition">
              <span class="text-yellow truncate">{t.title ?? 'Toque'}</span>
              {#if t.date}<span class="text-sm text-cold-light shrink-0">{t.date}</span>{/if}
            </a></li>
          {/each}
        </ul>
      {/if}
      {#if pastToques.length}
        <div class="text-cold-light text-sm -mb-1 {upcomingToques.length ? 'mt-2' : ''}">Anteriores</div>
        <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
          {#each pastToques as t}
            <li><a href={`/parties/${t.id}`} class="bg-base-900 px-4 py-3 flex items-center justify-between gap-3 hover:bg-base-950 transition">
              <span class="text-white/80 truncate">{t.title ?? 'Toque'}</span>
              {#if t.date}<span class="text-sm text-cold-light shrink-0">{t.date}</span>{/if}
            </a></li>
          {/each}
        </ul>
      {/if}
    {/if}
  {/if}
</div>
