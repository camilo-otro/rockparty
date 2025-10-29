<script lang="ts">
    import { ChevronLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { get } from 'svelte/store';
    import { user } from '$lib/stores/user';
    import VenueForm from '$lib/components/VenueForm.svelte';

    let submitting = false;
    let name = '';
    let address = '';
    let contactName = '';
    let contact = '';
    let whatsapp = '';
    let instagram = '';
    let success = false;
    let error = '';
    let userId: string | null = null;
    let isAuthenticated = false;
    let unsubscribeUser: () => void;

    let venueTypes: any[] = [];
    let selectedVenueType: string = '';

    let allowsParties: boolean = true;
    let allowsRehearsals: boolean = false;

    onMount(async () => {
        unsubscribeUser = user.subscribe(u => {
            isAuthenticated = !!u?.id;
            userId = u?.id ?? null;
        });
        // Fetch venue types
        const { supabase } = await import('$lib/supabaseClient');
        const { data: typesData, error: typesError } = await supabase.from('venue_type').select('id, name');
        if (!typesError && typesData) {
            venueTypes = typesData;
            if (venueTypes.length > 0) selectedVenueType = venueTypes[0].id;
        }
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
  <div class="mt-8 p-6 bg-yellow-100 text-yellow-800 rounded-lg text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para crear un local.
  </div>
{:else}
  {#if !success && !error}
    <VenueForm
      submitting={submitting}
      success={success}
      error={error}
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
      on:submit={async (e) => {
        submitting = true;
        error = '';
        const { name, address, contactName, contact, whatsapp, instagram, venueType, allowsParties, allowsRehearsals, admins } = e.detail;
        try {
          const { supabase } = await import('$lib/supabaseClient');
          const { data, error: dbError } = await supabase
            .from('venue')
            .insert([{ name, address, contact_name: contactName, contact, whatsapp, instagram, venue_type: venueType, allow_party: allowsParties, allow_rehearsal: allowsRehearsals, created_by: userId }])
            .select();
          if (dbError) {
            error = `Error de base de datos: ${dbError.message}`;
          } else {
            // Add venue_admins
            if (data && data.length > 0 && admins && admins.length > 0) {
              await supabase.from('venue_admin').insert(admins.map((a: string) => ({ venue_id: data[0].id, user_id: a })));
            }
            success = true;
            setTimeout(() => {
              window.location.href = '/venues';
            }, 1000);
          }
        } catch (e) {
          error = 'No se pudo conectar con el servidor.';
        }
        submitting = false;
      }}
      on:error={(e) => error = e.detail}
    />
  {/if}
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Nuevo Local Creado!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
  {/if}
{/if}