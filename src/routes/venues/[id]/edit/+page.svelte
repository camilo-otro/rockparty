<script lang="ts">
// Imports
import { onMount } from 'svelte';
import { page } from '$app/state';
import { supabase } from '$lib/supabaseClient';
import VenueForm from '$lib/components/VenueForm.svelte';
import { ChevronLeft } from 'lucide-svelte';
import { goto } from '$app/navigation';
import { user } from '$lib/stores/user';
import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';

// State variables
let venue: any = null;
let venueTypes: any[] = [];
let venueAdmins: string[] = [];
let errorVenueTypes: string | null = null;
let submitting = false;
let currentUserId: string | null = null;
let equipmentOptions: any[] = [];
let initialEquipment: { equipment_id: number; quantity: number | null; notes: string | null }[] = [];

// Lifecycle
onMount(async () => {
  const id = page.params.id;
  user.subscribe(u => { currentUserId = u?.id ?? null; })();

  const [{ data: venueData }, { data: typesData, error: typesError }, { data: adminData }, { data: equipData }, { data: veData }] =
    await Promise.all([
      supabase.from('venue').select('*').eq('id', Number(id)).single(),
      supabase.from('venue_type').select('id, name'),
      supabase.from('venue_admin').select('user_id').eq('venue_id', Number(id)),
      supabase.from('equipment').select('id, name, category').order('id'),
      supabase.from('venue_equipment').select('equipment_id, quantity, notes').eq('venue_id', Number(id))
    ]);
  venueTypes = typesData ?? [];
  if (typesError) errorVenueTypes = typesError.message;
  venueAdmins = adminData ? adminData.map(a => a.user_id) : [];
  equipmentOptions = equipData ?? [];
  initialEquipment = (veData ?? []).map((r: any) => ({ equipment_id: r.equipment_id, quantity: r.quantity, notes: r.notes }));
  venue = venueData; // set last so the form mounts with everything ready
});
</script>

<div class="bg-cold-base p-4 flex-row">
  <h2 class="text-white text-2xl">EDITAR LOCAL</h2>
  <a href="/venues/{page.params.id}" class="text-lg text-bold text-cold-light"><ChevronLeft/></a>
</div>
{#if !venue}
  <div class="mt-8 p-6 text-white">Cargando datos del local...</div>
{:else if !(currentUserId == venue.created_by || (venueAdmins && currentUserId && venueAdmins.includes(currentUserId)))}
  <div class="mt-8 p-6 text-red-500">No tienes permiso para editar los detalles de este local.</div>
{:else}
  <VenueForm
    submitting={submitting}
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
    equipmentOptions={equipmentOptions}
    initialEquipment={initialEquipment}
    initialRequiresApproval={venue.requires_approval ?? true}
    initialEngagementModel={venue.engagement_model ?? ''}
    initialEngagementNotes={venue.engagement_notes ?? ''}
    initialMinAge={venue.min_age ?? null}
    initialCurfew={venue.curfew ?? ''}
    initialCapacity={venue.capacity ?? null}
    initialHouseRules={venue.house_rules ?? ''}
    initialIsTest={venue.is_test}
    on:submit={async (e) => {
      submitting = true;
      const { name, address, contactName, contact, whatsapp, instagram, venueType, allowsParties, allowsRehearsals, admins,
              equipment, requiresApproval, engagementModel, engagementNotes, minAge, curfew, capacity, houseRules, isTest } = e.detail;
      try {
        const { error: dbError } = await supabase
          .from('venue')
          .update({ name, address, contact_name: contactName, contact, whatsapp, instagram, venue_type: venueType, allow_party: allowsParties, allow_rehearsal: allowsRehearsals,
                    requires_approval: requiresApproval, engagement_model: engagementModel, engagement_notes: engagementNotes, min_age: minAge, curfew, capacity, house_rules: houseRules, is_test: isTest })
          .eq('id', venue.id);
        if (dbError) {
          reportError(dbError);
        } else {
          // Update venue_admin table
          const initialAdminSet = new Set(venueAdmins);
          const updatedAdminSet = new Set(admins);
          const adminsToRemove = venueAdmins.filter(a => !updatedAdminSet.has(a));
          const adminsToAdd = admins.filter((a: string) => !initialAdminSet.has(a));
          if (adminsToRemove.length > 0) {
            await supabase.from('venue_admin').delete().eq('venue_id', venue.id).in('user_id', adminsToRemove);
          }
          if (adminsToAdd.length > 0) {
            await supabase.from('venue_admin').insert(adminsToAdd.map((a: string) => ({ venue_id: venue.id, user_id: a })));
          }
          // Replace venue_equipment. The set is small and quantity/notes can
          // change on already-selected items, so delete-all + insert is simpler
          // and more correct than diffing three fields.
          await supabase.from('venue_equipment').delete().eq('venue_id', venue.id);
          if (equipment && equipment.length > 0) {
            await supabase.from('venue_equipment').insert(
              (equipment as any[]).map((eq) => ({ venue_id: venue.id, equipment_id: eq.equipment_id, quantity: eq.quantity, notes: eq.notes }))
            );
          }
          toastSuccess('¡Local actualizado!');
          setTimeout(() => {
            goto(`/venues/${venue.id}`);
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
