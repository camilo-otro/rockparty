<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ChevronLeft, Edit, Users, HandMetal } from 'lucide-svelte';
  import { goto } from '$app/navigation';
  import { user } from '$lib/stores/user';

  let performer: any = null;
  let instruments: string[] = [];
  // Credits (#95 Stage 4): roles this person has actually been trusted with on
  // toques that have already happened. No new schema — a read of the record
  // Stage 2 writes. Honest by construction: it comes from ORGANIZERS naming
  // them, not from self-declaration.
  let credits: { name: string; count: number }[] = [];
  let bands: { id: number; name: string; avatar_url: string | null }[] = []; // #72
  let loading = true;
  let error: string | null = null;
  let currentUserId: string | null = null;
  // Applause received (#38). Kept SEPARATE per target type rather than summed:
  // "great all night" and "great on that song" are different endorsements, and
  // merging them would also quietly reward whoever played the most songs.
  let nightClaps = 0;
  let songClaps = 0;

  // Local date parts, not toISOString() — that is UTC and can shift the day.
  const _now = new Date();
  const todayStr = `${_now.getFullYear()}-${String(_now.getMonth() + 1).padStart(2, '0')}-${String(_now.getDate()).padStart(2, '0')}`;

  onMount(async () => {
    const id = get(page).params.id;
    user.subscribe(u => { currentUserId = u?.id ?? null; })();

    const { data, error: err } = await supabase.from('profile').select('id, nickname, avatar_url').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      performer = data;
      const [{ data: instrData }, { data: bandRows }, nightRes, songRes, creditRes] = await Promise.all([
        supabase.from('profile_instrument').select('instrument(name)').eq('profile_id', id),
        // RLS hides test bands from non-devs, so this shows only the viewer-visible ones.
        supabase.from('band_member').select('band ( id, name, avatar_url )').eq('user_id', id),
        // head+count: we want the tallies, not the rows.
        supabase.from('applause').select('id', { count: 'exact', head: true })
          .eq('performer_id', id).eq('target_type', 'performer'),
        supabase.from('applause').select('id', { count: 'exact', head: true })
          .eq('performer_id', id).eq('target_type', 'song_performer'),
        // Past toques only: an upcoming assignment is not something they have
        // DONE. `!inner` so the date filter restricts rows rather than nulling
        // the embed. RLS scopes this to toques the viewer can see, so a test
        // toque never shows up as a credit.
        supabase.from('party_requirement')
          .select('role:role_id ( name ), party!inner(date)')
          .eq('assigned_user', id)
          .eq('kind', 'role')
          .lt('party.date', todayStr)
      ]);
      nightClaps = nightRes.count ?? 0;
      songClaps = songRes.count ?? 0;
      instruments = (instrData ?? []).map((r: any) => r.instrument?.name).filter(Boolean);
      bands = (bandRows ?? []).map((r: any) => r.band).filter(Boolean);
      const tally: Record<string, number> = {};
      for (const row of (creditRes.data ?? []) as any[]) {
        const name = row.role?.name;
        if (name) tally[name] = (tally[name] ?? 0) + 1;
      }
      credits = Object.entries(tally)
        .map(([name, count]) => ({ name, count }))
        .sort((a, b) => b.count - a.count);
    }
    loading = false;
  });
</script>

<div class="mt-8">
  <div class="mb-4 mx-4">
    <a href="/performers" class="text-bold text-cold-light flex items-center gap-2"><ChevronLeft/>VOLVER</a>
  </div>
  {#if loading}
    <div class="text-white p-6">Cargando...</div>
  {:else if error}
    <div class="text-red-500 p-6">Error: {error}</div>
  {:else if performer}
    <div class="p-6">
      <div class="flex justify-center">
        <img
          src={performer.avatar_url && performer.avatar_url.trim() !== '' ? performer.avatar_url : '/images/avatar-default.svg'}
          alt="Avatar"
          class="w-32 h-32 rounded-full mb-4 border border-cold-base"
        />
      </div>
      <h2 class="text-3xl text-yellow font-medium mb-2 text-center">{performer.nickname}</h2>

      {#if nightClaps || songClaps}
        <div class="flex items-center justify-center gap-6 mb-2">
          {#if nightClaps}
            <div class="flex flex-col items-center">
              <span class="text-2xl text-yellow inline-flex items-center gap-1.5"><HandMetal size={18} /> {nightClaps}</span>
              <span class="text-[0.65rem] uppercase tracking-widest text-cold-light/70">por sus noches</span>
            </div>
          {/if}
          {#if songClaps}
            <div class="flex flex-col items-center">
              <span class="text-2xl text-yellow inline-flex items-center gap-1.5"><HandMetal size={18} /> {songClaps}</span>
              <span class="text-[0.65rem] uppercase tracking-widest text-cold-light/70">por canciones</span>
            </div>
          {/if}
        </div>
      {/if}

      <section class="mt-6">
        <h3 class="text-lg text-white mb-2">Instrumentos</h3>
        {#if instruments.length === 0}
          <div class="text-cold-light">Aún no ha agregado instrumentos.</div>
        {:else}
          <div class="flex flex-row flex-wrap gap-2">
            {#each instruments as name}
              <span class="px-3 py-1 rounded-full text-sm bg-cold-base text-white">{name}</span>
            {/each}
          </div>
        {/if}
      </section>

      {#if credits.length}
        <section class="mt-6">
          <h3 class="text-lg text-white mb-2">Ha trabajado como</h3>
          <div class="flex flex-row flex-wrap gap-2">
            {#each credits as c}
              <span class="px-3 py-1 rounded-full text-sm border border-yellow/50 text-yellow">
                {c.name} · {c.count} {c.count === 1 ? 'toque' : 'toques'}
              </span>
            {/each}
          </div>
        </section>
      {/if}

      {#if bands.length}
        <section class="mt-6">
          <h3 class="text-lg text-white mb-2">Toca en</h3>
          <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
            {#each bands as b}
              <li><a href={`/bands/${b.id}`} class="bg-base-900 px-4 py-3 flex items-center gap-3 hover:bg-base-950 transition">
                {#if b.avatar_url}
                  <img src={b.avatar_url} alt={b.name} class="w-8 h-8 rounded-full object-cover border border-cold-base" />
                {:else}
                  <span class="w-8 h-8 rounded-full bg-base-950 flex items-center justify-center"><Users size={16} class="text-cold-light" /></span>
                {/if}
                <span class="text-yellow">{b.name}</span>
              </a></li>
            {/each}
          </ul>
        </section>
      {/if}

      {#if currentUserId === performer.id}
        <div class="flex justify-center">
          <button
            class="text-center bg-cold-base text-white font-medium px-4 py-2 rounded-lg mt-8"
            on:click={() => goto(`/performers/${performer.id}/edit`)}
          >Editar perfil<Edit class="inline ml-2" size={16} /></button>
        </div>
      {/if}
    </div>
  {/if}
</div>
