<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, Edit, Instagram } from 'lucide-svelte';
  import { user } from '$lib/stores/user';

  let venue: any = null;
  let venueType: any = null;
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
      
      // Fetch venue type name
      if (venue.venue_type) {
        const { data: venueTypeData } = await supabase.from('venue_type').select('name').eq('id', venue.venue_type).single();
        venueType = venueTypeData;
      }
      
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
      {#if venue.whatsapp}
        <div class="mb-2 text-cold-light">
          <a href="https://wa.me/{venue.whatsapp}" target="_blank" class="text-green-400 hover:underline flex flex-row items-center">
            <svg class="mr-2" width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
              <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893A11.821 11.821 0 0020.525 3.687"/>
            </svg>
            {venue.whatsapp}
          </a>
        </div>
      {/if}
      {#if venue.instagram}
        <div class="mb-2 text-cold-light">
          <a href="https://instagram.com/{venue.instagram}" target="_blank" class="text-pink-400 hover:underline flex flex-row items-center">
            <Instagram class="mr-2" size={16} />{venue.instagram}
          </a>
        </div>
      {/if}
      <div class="mb-2 text-cold-light">Tipo de local: {venueType?.name || 'No especificado'}</div>
      {#if venue.allow_party}
        <div class="mb-2 text-cold-light">Permite fiestas</div>
      {/if}
      {#if venue.allow_rehearsal}
        <div class="mb-2 text-cold-light">Permite ensayos</div>
      {/if}
    </div>
  {/if}
</div>
