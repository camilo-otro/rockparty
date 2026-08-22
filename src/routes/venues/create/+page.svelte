<script lang="ts">
    import { ChevronLeft } from 'lucide-svelte';
    import { onMount, onDestroy } from 'svelte';
    import { get } from 'svelte/store';
    import { user } from '$lib/stores/user';
    import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
    import VenueForm from '$lib/components/VenueForm.svelte';

    let submitting = false;
    let name = '';
    let address = '';
    let contactName = '';
    let contact = '';
    let whatsapp = '';
    let instagram = '';
    let userId: string | null = null;
    let isAuthenticated = false;
    let unsubscribeUser: () => void;

    let venueTypes: any[] = [];
    let selectedVenueType: string = '';

    let allowsParties: boolean = true;
    let allowsRehearsals: boolean = false;
    let equipmentOptions: any[] = [];

    onMount(async () => {
        unsubscribeUser = user.subscribe(u => {
            isAuthenticated = !!u?.id;
            userId = u?.id ?? null;
        });
        // Fetch venue types + equipment lookup
        const { supabase } = await import('$lib/supabaseClient');
        const { data: typesData, error: typesError } = await supabase.from('venue_type').select('id, name');
        if (!typesError && typesData) {
            venueTypes = typesData;
            if (venueTypes.length > 0) selectedVenueType = venueTypes[0].id;
        }
        const { data: equipData } = await supabase.from('equipment').select('id, name, category').order('id');
        equipmentOptions = equipData ?? [];
    });

    onDestroy(() => {
        if (unsubscribeUser) unsubscribeUser();
    });

    function loginWithGoogle() {
      import('$lib/supabaseClient').then(({ supabase }) => {
        supabase.auth.signInWithOAuth({
          provider: 'google',
          options: { redirectTo: window.location.href }
        });
      });
    }
</script>
<div class="bg-cold-base p-4 flex-row">
    <h2 class="text-white text-2xl">AGREGAR NUEVO LOCAL</h2>
    <a href="/venues" class="text-lg text-bold text-cold-light"><ChevronLeft/></a>
</div>
{#if !isAuthenticated}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para crear un local.
  </div>
{:else}
  <VenueForm
      submitting={submitting}
      initialName={name}
      initialAddress={address}
      initialContactName={contactName}
      initialContact={contact}
      initialWhatsapp={whatsapp}
      initialInstagram={instagram}
      initialVenueType={selectedVenueType}
      venueTypes={venueTypes}
      initialAllowsParties={allowsParties}
      initialAllowsRehearsals={allowsRehearsals}
      userId={userId}
      isAuthenticated={isAuthenticated}
      initialAdmins={[]}
      equipmentOptions={equipmentOptions}
      on:submit={async (e) => {
        submitting = true;
        const { name, address, contactName, contact, whatsapp, instagram, venueType, allowsParties, allowsRehearsals, admins,
                equipment, requiresApproval, engagementModel, engagementNotes, minAge, curfew, capacity, houseRules } = e.detail;
        try {
          const { supabase } = await import('$lib/supabaseClient');
          const { data, error: dbError } = await supabase
            .from('venue')
            .insert([{ name, address, contact_name: contactName, contact, whatsapp, instagram, venue_type: venueType, allow_party: allowsParties, allow_rehearsal: allowsRehearsals, created_by: userId,
                       requires_approval: requiresApproval, engagement_model: engagementModel, engagement_notes: engagementNotes, min_age: minAge, curfew, capacity, house_rules: houseRules }])
            .select();
          if (dbError) {
            reportError(dbError);
          } else {
            const newVenueId = data && data.length > 0 ? data[0].id : null;
            // Add venue_admins
            if (newVenueId && admins && admins.length > 0) {
              await supabase.from('venue_admin').insert(admins.map((a: string) => ({ venue_id: newVenueId, user_id: a })));
            }
            // Add equipment (with quantity + description)
            if (newVenueId && equipment && equipment.length > 0) {
              await supabase.from('venue_equipment').insert(
                equipment.map((eq: any) => ({ venue_id: newVenueId, equipment_id: eq.equipment_id, quantity: eq.quantity, notes: eq.notes }))
              );
            }
            toastSuccess('¡Nuevo local creado!');
            setTimeout(() => {
              window.location.href = '/venues';
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