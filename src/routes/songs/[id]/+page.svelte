<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ChevronLeft } from 'lucide-svelte';

  let song: any = null;
  let loading = true;
  let error: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('song').select('*').eq('id', Number(id)).single();
    if (err) {
      error = err.message;
    } else {
      song = data;
    }
    loading = false;
  });
</script>

<div class="mt-8">
  <div class="mb-4">
    <a href="/songs" class="text-bold text-cold-light flex items-center gap-2"><ChevronLeft/>VOLVER</a>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if song}
    <div class="p-6 bg-slate-100 rounded-lg shadow">
      <h2 class="text-2xl font-bold mb-2">{song.title}</h2>
      <div class="mb-2 text-slate-700">Artista: {song.artist}</div>
      <div class="mb-2 text-slate-700">Tonalidad: {song.key}</div>
      <a href="/songs" class="text-cold-light"><ChevronLeft />Volver a la lista</a>
    </div>
  {/if}
</div>
