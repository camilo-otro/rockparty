<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, Edit } from 'lucide-svelte';
  import { user } from '$lib/stores/user';

  let venue: any = null;
  let loading = true;
  let error: string | null = null;
  let venueAdmins: string[] = [];
  let currentUserId: string | null = null;

  onMount(async () => {
    const id = page.params.id;
    const { data, error: err } = await supabase.from('venue').select('*').eq('id', id).single();
    if (err) {
      error = err.message;
    } else {
      venue = data;
      // Fetch venue admins
      const { data: adminData } = await supabase.from('venue_admin').select('user_id').eq('venue_id', id);
      venueAdmins = adminData ? adminData.map(a => a.user_id) : [];
    }
    user.subscribe(u => {
      currentUserId = u?.id ?? null;
    })();
    loading = false;
  });

  function handleEdit() {
    if (venue?.id) {
      window.location.href = `/venues/${venue.id}/edit`;
    }
  }
</script>

<div class="max-w-xl mx-auto mt-2">
  <div class="flex flex-row w-full justify-between">
    <a href="/venues" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft/>VOLVER</a>
    <div class="flex flex-row w-auto gap-2 m-4">
      {#if currentUserId == venue?.created_by || (venueAdmins && currentUserId && venueAdmins.includes(currentUserId))}
        <button on:click={handleEdit} class="bg-cold-light text-black rounded-lg px-2 py-1 inline-flex items-center gap-2">
          <Edit size={18} />
        </button>
      {/if}
    </div>
  </div>
  {#if loading}
    <div class="text-white p-4">Cargando...</div>
  {:else if error}
    <div class="text-red-500 p-4">Error: {error}</div>
  {:else if venue}
    <div class="px-6 p-2 bg-base-900 rounded-lg shadow mx-4">
      <h2 class="text-3xl text-yellow font-bold mb-2">{venue.name}</h2>
      <div class="mb-2 text-white">Dirección: {venue.address}</div>
      <div class="mb-2 text-cold-light">Persona de contacto: {venue.contact_name}</div>
      <div class="mb-2 text-cold-light">Contacto: {venue.contact}</div>
      <div class="mb-2 text-cold-light">Tipo de local: {venue.venue_type}</div>
      <div class="mb-2 text-cold-light">Permite fiestas: {venue.allow_party ? 'Sí' : 'No'}</div>
      <div class="mb-2 text-cold-light">Permite ensayos: {venue.allow_rehearsal ? 'Sí' : 'No'}</div>
    </div>
  {/if}
</div>
