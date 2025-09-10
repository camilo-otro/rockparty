<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import PartyForm from '$lib/components/PartyForm.svelte';
  import { user } from '$lib/stores/user';
  import { ArrowLeft } from 'lucide-svelte';

  let party: any = null;
  let venues: any[] = [];
  let loadingVenues = true;
  let errorVenues: string | null = null;
  let submitting = false;
  let success = false;
  let error = '';
  let partyAdmins: string[] = [];
  let currentUserId: string | null = null;

  onMount(async () => {
    const id = page.params.id;
    const { data: partyData, error: partyErr } = await supabase.from('party').select('*').eq('id', id).single();
    party = partyData;
    const { data: venueData, error: venueErr } = await supabase.from('venue').select('id, name');
    if (venueErr) {
      errorVenues = venueErr.message;
    } else {
      venues = venueData ?? [];
    }
    // Fetch party admins
    const { data: adminData } = await supabase.from('party_admin').select('user_id').eq('party_id', id);
    partyAdmins = adminData ? adminData.map(a => a.user_id) : [];
    // Get current user id
    user.subscribe(u => {
      currentUserId = u?.id ?? null;
    })();
    loadingVenues = false;
  });
</script>

<div class="bg-cold-base p-4 flex-row">
  <h2 class="text-white text-2xl">EDITAR FIESTA</h2>
  <a href="/parties" class="text-lg text-bold text-cold-light"><ArrowLeft/></a>
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
    submitting={submitting}
    success={success}
    error={error}
    userId={party.created_by}
    isAuthenticated={true}
    on:submit={async (e) => {
      submitting = true;
      error = '';
      const { title, description, date, venue, admins } = e.detail;
      try {
        const { error: dbError } = await supabase
          .from('party')
          .update({ title, description, date, venue })
          .eq('id', party.id);
        if (dbError) {
          error = `Database error: ${dbError.message}`;
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
          success = true;
          setTimeout(() => {
            window.location.href = `/parties/${party.id}`;
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
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center">
      Fiesta actualizada!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center">
      Error: {error}
    </div>
  {/if}
{/if}
