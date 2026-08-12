<script lang="ts">
// Imports
import { onMount } from 'svelte';
import { page } from '$app/state';
import { supabase } from '$lib/supabaseClient';
import VenueForm from '$lib/components/VenueForm.svelte';
import { ChevronLeft } from 'lucide-svelte';
import { user } from '$lib/stores/user';

// State variables
let venue: any = null;
let venueTypes: any[] = [];
let venueAdmins: string[] = [];
let loadingVenueTypes = true;
let errorVenueTypes: string | null = null;
let submitting = false;
let success = false;
let error = '';
let currentUserId: string | null = null;

// Lifecycle
onMount(async () => {
  const id = page.params.id;
  // Fetch venue
  const { data: venueData, error: venueErr } = await supabase.from('venue').select('*').eq('id', Number(id)).single();
  venue = venueData;
  // Fetch venue types
  const { data: typesData, error: typesError } = await supabase.from('venue_type').select('id, name');
  venueTypes = typesData ?? [];
  if (typesError) errorVenueTypes = typesError.message;
  // Fetch venue admins
  const { data: adminData } = await supabase.from('venue_admin').select('user_id').eq('venue_id', Number(id));
  venueAdmins = adminData ? adminData.map(a => a.user_id) : [];
  // Get current user id
  user.subscribe(u => {
    currentUserId = u?.id ?? null;
  })();
  loadingVenueTypes = false;
});

// Render
</script>

<div class="bg-cold-base p-4 flex-row">
  <h2 class="text-white text-2xl">EDITAR LOCAL</h2>
  <a href="/venues" class="text-lg text-bold text-cold-light"><ChevronLeft/></a>
</div>
{#if !venue}
  <div class="mt-8 p-6 text-white">Cargando datos del local...</div>
{:else if !(currentUserId == venue.created_by || (venueAdmins && currentUserId && venueAdmins.includes(currentUserId)))}
  <div class="mt-8 p-6 text-red-500">No tienes permiso para editar los detalles de este local.</div>
{:else}
  <VenueForm
    submitting={submitting}
    success={success}
    error={error}
    initialName={venue.name}
    initialAddress={venue.address}
    initialContactName={venue.contact_name}
    initialContact={venue.contact}
    initialWhatsapp={venue.whatsapp || ''}
    initialInstagram={venue.instagram || ''}
    initialVenueType={venue.venue_type}
    venueTypes={venueTypes}
    initialAllowsParties={venue.allow_party}
    initialAllowsRehearsals={venue.allow_rehearsal}
    userId={venue.created_by}
    isAuthenticated={true}
    initialAdmins={venueAdmins}
    on:submit={async (e) => {
      submitting = true;
      error = '';
      const { name, address, contactName, contact, whatsapp, instagram, venueType, allowsParties, allowsRehearsals, admins } = e.detail;
      try {
        const { error: dbError } = await supabase
          .from('venue')
          .update({ name, address, contact_name: contactName, contact, whatsapp, instagram, venue_type: venueType, allow_party: allowsParties, allow_rehearsal: allowsRehearsals })
          .eq('id', venue.id);
        if (dbError) {
          error = `Error de base de datos: ${dbError.message}`;
        } else {
          // Update venue_admin table
          const initialSet = new Set(venueAdmins);
          const updatedSet = new Set(admins);
          // Admins to remove
          const toRemove = venueAdmins.filter(a => !updatedSet.has(a));
          // Admins to add
          const toAdd = admins.filter((a: string) => !initialSet.has(a));
          if (toRemove.length > 0) {
            await supabase.from('venue_admin').delete().eq('venue_id', venue.id).in('user_id', toRemove);
          }
          if (toAdd.length > 0) {
            await supabase.from('venue_admin').insert(toAdd.map((a: string) => ({ venue_id: venue.id, user_id: a })));
          }
          success = true;
          setTimeout(() => {
            window.location.href = `/venues/${venue.id}`;
          }, 1000);
        }
      } catch (e) {
        error = 'No se pudo conectar con el servidor.';
      }
      submitting = false;
    }}
    on:error={(e) => error = e.detail}
  />
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-lg text-center">
      Local actualizado!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-lg text-center">
      Error: {error}
    </div>
  {/if}
{/if}
