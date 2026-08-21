<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ChevronLeft, Edit } from 'lucide-svelte';
  import { user } from '$lib/stores/user';

  let performer: any = null;
  let instruments: string[] = [];
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
      const { data: instrData } = await supabase
        .from('profile_instrument')
        .select('instrument(name)')
        .eq('profile_id', id);
      instruments = (instrData ?? []).map((r: any) => r.instrument?.name).filter(Boolean);
    }
    loading = false;
  });
</script>

<div class="max-w-xl mx-auto mt-8">
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

      {#if currentUserId === performer.id}
        <div class="flex justify-center">
          <button
            class="text-center bg-cold-base text-white font-medium px-4 py-2 rounded-lg mt-8"
            on:click={() => window.location.href = `/performers/${performer.id}/edit`}
          >Editar perfil<Edit class="inline ml-2" size={16} /></button>
        </div>
      {/if}
    </div>
  {/if}
</div>
