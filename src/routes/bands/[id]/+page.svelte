<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { ChevronLeft, Crown, Edit, Users } from 'lucide-svelte';

  const bandId = Number(page.params.id);
  let currentUserId: string | null = null;
  let loading = true;
  let band: any = null;
  let members: { user_id: string; nickname: string; role: string; instruments: string[] }[] = [];
  let isManager = false;
  let unsub: () => void;

  onMount(async () => {
    unsub = user.subscribe((u) => { currentUserId = u?.id ?? null; });
    const [{ data: b }, { data: mem }, { data: bmi }, { data: instr }] = await Promise.all([
      supabase.from('band').select('id, name, bio, is_test').eq('id', bandId).maybeSingle(),
      supabase.from('band_member').select('user_id, role, profile ( nickname )').eq('band_id', bandId),
      supabase.from('band_member_instrument').select('user_id, instrument_id').eq('band_id', bandId),
      supabase.from('instrument').select('id, name')
    ]);
    band = b;
    if (band) {
      const iName = new Map((instr ?? []).map((i: any) => [i.id, i.name]));
      const instByUser: Record<string, string[]> = {};
      for (const r of bmi ?? []) (instByUser[r.user_id] ??= []).push(iName.get(r.instrument_id));
      members = (mem ?? [])
        .map((m: any) => ({ user_id: m.user_id, nickname: m.profile?.nickname ?? '—', role: m.role, instruments: (instByUser[m.user_id] ?? []).filter(Boolean) }))
        .sort((a, b) => (a.role === b.role ? 0 : a.role === 'manager' ? -1 : 1));
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
      <div class="bg-base-900 rounded-full p-3"><Users class="text-cold-light" size={28} /></div>
      <div class="flex flex-col gap-1">
        <h1 class="text-4xl text-yellow font-medium leading-none">{band.name}</h1>
        {#if band.is_test}<span class="self-start text-[0.65rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-warm-base text-warm-base">Datos de prueba</span>{/if}
      </div>
    </div>
    {#if band.bio}<p class="text-white/90 leading-snug">{band.bio}</p>{/if}

    <h2 class="text-xl text-white mt-2">INTEGRANTES · {members.length}</h2>
    <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
      {#each members as m}
        <li class="bg-base-900 px-4 py-3 flex items-center justify-between gap-3">
          <div>
            <div class="text-white flex items-center gap-2">
              {m.nickname}
              {#if m.role === 'manager'}<Crown size={13} class="text-yellow" />{/if}
            </div>
            {#if m.instruments.length}<div class="text-sm text-cold-light">{m.instruments.join(' · ')}</div>{/if}
          </div>
        </li>
      {/each}
    </ul>
  {/if}
</div>
