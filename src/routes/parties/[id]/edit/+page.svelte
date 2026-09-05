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
// Cancelling the toque moved here from the detail page — it's destructive, rare
// and admin-only, so it belongs behind the edit gate rather than on the page
// every musician and attendee reads. Two-step so it can't go off on one tap.
let confirmingCancel = false;
let cancelling = false;

// A terminal toque has nothing left to cancel.
$: canCancel = party && party.status !== 'cancelled' && party.status !== 'completed';

async function cancelToque() {
  if (!party || cancelling) return;
  cancelling = true;
  try {
    // .select() so a silent RLS denial (0 rows) is distinguishable from success.
    const { data, error } = await supabase
      .from('party')
      .update({ status: 'cancelled', cancel_reason: 'organizer' })
      .eq('id', party.id)
      .select('id');
    if (error) { reportError(error); return; }
    if (!data || data.length === 0) { toastError('No tienes permiso para cancelar este toque.'); return; }
    toastSuccess('Toque cancelado.');
    setTimeout(() => goto(`/parties/${party.id}`), 800);
  } catch {
    toastError('No se pudo conectar con el servidor.');
  } finally {
    cancelling = false;
    confirmingCancel = false;
  }
}

// Lifecycle
onMount(async () => {
  const id = page.params.id;
  // Resolve the current user FIRST so the permission gate never renders with a
  // null user (which flashed "No tienes permiso" before the check settled).
  user.subscribe(u => { currentUserId = u?.id ?? null; })();

  const [{ data: partyData }, { data: venueData, error: venueErr }, { data: adminData }] =
    await Promise.all([
      supabase.from('party').select('*').eq('id', Number(id)).single(),
      supabase.from('venue').select('id, name'),
      supabase.from('party_admin').select('user_id').eq('party_id', Number(id))
    ]);
  venues = venueData ?? [];
  if (venueErr) errorVenues = venueErr.message;
  partyAdmins = adminData ? adminData.map(a => a.user_id) : [];
  loadingVenues = false;
  party = partyData; // set last so the gate sees user + admins already resolved
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
    initialIsTest={party.is_test}
    excludePartyId={party.id}
    submitLabel="Guardar"
    submittingLabel="Guardando..."
    submitting={submitting}
    userId={party.created_by}
    isAuthenticated={true}
    on:submit={async (e) => {
      submitting = true;
      const { title, description, date, venue, admins, performerApproval, isTest } = e.detail;
      try {
        const { error: dbError } = await supabase
          .from('party')
          .update({ title, description, date, venue, performer_approval: performerApproval, is_test: isTest })
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

  {#if canCancel}
    <div class="m-4 mt-8 rounded-lg border border-red-400/30 p-4 flex flex-col gap-3">
      <div class="flex flex-col gap-1">
        <h3 class="text-white">Cancelar el toque</h3>
        <p class="text-cold-light text-sm leading-snug">
          Dejará de ser visible para el público. El setlist se conserva y puedes clonarlo en un nuevo borrador más adelante.
        </p>
      </div>
      {#if confirmingCancel}
        <div class="flex items-center gap-3">
          <button type="button" on:click={cancelToque} disabled={cancelling} class="bg-red-500 hover:bg-red-400 text-white rounded-lg px-4 py-2 text-sm transition disabled:opacity-60">
            {cancelling ? 'Cancelando…' : 'Sí, cancelar el toque'}
          </button>
          <button type="button" on:click={() => (confirmingCancel = false)} class="text-cold-light hover:text-white text-sm px-2 py-2 transition">Volver</button>
        </div>
      {:else}
        <button type="button" on:click={() => (confirmingCancel = true)} class="self-start text-red-400 hover:text-red-300 text-sm border border-red-400/40 hover:border-red-300 rounded-lg px-3 py-1 transition">
          Cancelar toque
        </button>
      {/if}
    </div>
  {/if}
{/if}
