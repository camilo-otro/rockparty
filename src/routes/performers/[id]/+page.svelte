<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ChevronLeft, Edit } from 'lucide-svelte';

  let performer: any = null;
  let loading = true;
  let error: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('profile').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      performer = data;
    }
    loading = false;
  });
</script>

<div class="max-w-xl mx-auto mt-8">
  <div class="mb-4">
    <a href="/performers" class="text-bold text-cold-light flex items-center gap-2"><ChevronLeft/>VOLVER</a>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if performer}
    <div class="p-6">
      <div class="flex justify-center">
        <img src={performer.avatar_url} alt="User Avatar" class="w-32 h-32 rounded-full mb-4" />
      </div>
      <h2 class="text-3xl text-yellow font-medium mb-2">{performer.nickname}</h2>
      <div class="mb-2 text-white">{performer.email}</div>
      <div class="flex justify-center">
        <button class="btn btn-accent text-center bg-cold-base font-medium px-4 py-2 rounded-lg mt-4" on:click={() => window.location.href = `/performers/${performer.id}/edit`}>Editar perfil<Edit class="inline ml-2" size={16} /></button>
      </div>
    </div>
  {/if}
</div>
