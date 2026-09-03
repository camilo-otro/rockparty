<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ChevronLeft, Edit, Users } from 'lucide-svelte';
  import { goto } from '$app/navigation';
  import { user } from '$lib/stores/user';

  let performer: any = null;
  let instruments: string[] = [];
  let bands: { id: number; name: string; avatar_url: string | null }[] = []; // #72
  let loading = true;
  let error: string | null = null;
  let currentUserId: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    user.subscribe(u => { currentUserId = u?.id ?? null; })();

    const { data, error: err } = await supabase.from('profile').select('id, nickname, avatar_url').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      performer = data;
      const [{ data: instrData }, { data: bandRows }] = await Promise.all([
        supabase.from('profile_instrument').select('instrument(name)').eq('profile_id', id),
        // RLS hides test bands from non-devs, so this shows only the viewer-visible ones.
        supabase.from('band_member').select('band ( id, name, avatar_url )').eq('user_id', id)
      ]);
      instruments = (instrData ?? []).map((r: any) => r.instrument?.name).filter(Boolean);
      bands = (bandRows ?? []).map((r: any) => r.band).filter(Boolean);
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
