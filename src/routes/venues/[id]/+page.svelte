<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { supabase } from '$lib/supabaseClient';
  import { get } from 'svelte/store';

  let venue: any = null;
  let loading = true;
  let error: string | null = null;

  onMount(async () => {
    const id = get(page).params.id;
    const { data, error: err } = await supabase.from('venue').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      venue = data;
    }
    loading = false;
  });
</script>

<div class="max-w-xl mx-auto mt-8">
  {#if loading}
    <div>Cargando...</div>
  {:else if error}
    <div class="text-red-500">Error: {error}</div>
  {:else if venue}
    <div class="p-6 bg-slate-100 rounded shadow">
      <h2 class="text-2xl font-bold mb-2">{venue.name}</h2>
      <div class="mb-2 text-slate-700">Dirección: {venue.address}</div>
      <div class="mb-2 text-slate-700">Contacto: {venue.contact_name} ({venue.contact})</div>
      <a href="/venues" class="text-blue-600 hover:underline">&larr; Volver a la lista</a>
    </div>
  {/if}
</div>
