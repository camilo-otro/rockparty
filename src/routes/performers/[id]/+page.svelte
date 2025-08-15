<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';
  import { ArrowLeft } from 'lucide-svelte';

  let performer: any = null;
  let loading = true;
  let error: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('user').select('*').eq('id', id).single();
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
    <a href="/performers" class="text-lg text-bold text-slate-700 flex items-center gap-2"><ArrowLeft/> Volver</a>
  </div>
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if performer}
    <div class="p-6 bg-slate-100 rounded shadow">
      <h2 class="text-2xl font-bold mb-2">{performer.nickname}</h2>
      <div class="mb-2 text-slate-700">Role: {performer.role}</div>
      <a href="/performers" class="text-blue-600 hover:underline">&larr; Volver a la lista</a>
    </div>
  {/if}
</div>
