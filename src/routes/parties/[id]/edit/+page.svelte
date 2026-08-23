<script lang="ts">
// Imports
import { onMount } from 'svelte';
import { page } from '$app/state';
import { supabase } from '$lib/supabaseClient';
import PartyForm from '$lib/components/PartyForm.svelte';
import { user } from '$lib/stores/user';
import { ChevronLeft } from 'lucide-svelte';
import { goto } from '$app/navigation';
import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';

// State variables
let party: any = null;
let venues: any[] = [];
let loadingVenues = true;
let errorVenues: string | null = null;
let submitting = false;
let partyAdmins: string[] = [];
let currentUserId: string | null = null;

// Lifecycle
onMount(async () => {
  const id = page.params.id;
  // Fetch party
  const { data: partyData, error: partyErr } = await supabase.from('party').select('*').eq('id', Number(id)).single();
  party = partyData;
  // Fetch venues
  const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name');
  venues = venueData ?? [];
  if (venueErr) errorVenues = venueErr.message;
  // Fetch party admins
  const { data: adminData } = await supabase.from('party_admin').select('user_id').eq('party_id', Number(id));
  partyAdmins = adminData ? adminData.map(a => a.user_id) : [];
  // Get current user id
  user.subscribe(u => {
    currentUserId = u?.id ?? null;
  })();
  loadingVenues = false;
});

// Render
</script>

<div class="bg-cold-base p-4 flex-row">
  <h2 class="text-white text-2xl">EDITAR FIESTA</h2>
  <a href="/parties/{page.params.id}" class="text-lg text-bold text-cold-light"><ChevronLeft/></a>
</div>
{#if !party}
  <div class="mt-8 p-6 text-white">Cargando datos de la fiesta...</div>
{:else if !(currentUserId == party.created_by || (partyAdmins && currentUserId && partyAdmins.includes(currentUserId)))}
  <div class="mt-8 p-6 text-red-500">No tienes permiso para editar los detalles de esta fiesta.</div>
{:else}
  <PartyForm
    venues={venues}
    loadingVenues={loadingVenues}
    errorVenues={errorVenues}
    initialTitle={party.title}
    initialDescription={party.description}
    initialDate={party.date}
    initialVenue={party.venue}
    initialAdmins={partyAdmins}
    initialPerformerApproval={party.performer_approval}
    submitLabel="Guardar"
    submittingLabel="Guardando..."
    submitting={submitting}
    userId={party.created_by}
    isAuthenticated={true}
    on:submit={async (e) => {
      submitting = true;
      const { title, description, date, venue, admins, performerApproval } = e.detail;
      try {
        const { error: dbError } = await supabase
          .from('party')
          .update({ title, description, date, venue, performer_approval: performerApproval })
          .eq('id', party.id);
        if (dbError) {
          reportError(dbError);
        } else {
          // Update party_admin table
          const initialSet = new Set(partyAdmins);
          const updatedSet = new Set(admins);
          // Admins to remove
          const toRemove = partyAdmins.filter(a => !updatedSet.has(a));
          // Admins to add
          const toAdd = admins.filter((a: string) => !initialSet.has(a));
          if (toRemove.length > 0) {
            await supabase.from('party_admin').delete().eq('party_id', party.id).in('user_id', toRemove);
          }
          if (toAdd.length > 0) {
            await supabase.from('party_admin').insert(toAdd.map((a: string) => ({ party_id: party.id, user_id: a })));
          }
          toastSuccess('¡Toque actualizado!');
          setTimeout(() => {
            goto(`/parties/${party.id}`);
          }, 1000);
        }
      } catch (e) {
        toastError('No se pudo conectar con el servidor.');
      }
      submitting = false;
    }}
    on:error={(e) => toastError(e.detail)}
  />
{/if}
