<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { get } from 'svelte/store';
    import { user } from '$lib/stores/user';
    import { sanitizeString } from '$lib/sanitize';

    let submitting = false;
    let name = '';
    let address = '';
    let contactName = '';
    let contact = '';
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
            userId = u?.id ?? null;
            isAuthenticated = !!u?.id;
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

    async function handleSubmit() {
        if (!name || !address || !contactName || !contact || !selectedVenueType) {
            error = 'Todos los campos son obligatorios.';
            return;
        }
        // Sanitize inputs
        const safeName = sanitizeString(name);
        const safeAddress = sanitizeString(address);
        const safeContactName = sanitizeString(contactName);
        const safeContact = sanitizeString(contact);
        const safeVenueType = sanitizeString(selectedVenueType);
        submitting = true;
        error = '';
        try {
            const { supabase } = await import('$lib/supabaseClient');
            const { data, error: dbError } = await supabase
                .from('venue')
                .insert([{ name: safeName, address: safeAddress, contact_name: safeContactName, contact: safeContact, created_by: userId, venue_type: safeVenueType, allow_party: allowsParties, allow_rehearsal: allowsRehearsals }])
                .select();
                
            if (dbError) {
                error = `Error de base de datos: ${dbError.message}`;
            } else {
                success = true;
                setTimeout(() => {
                    window.location.href = '/venues';
                }, 1000);
            }
        } catch (e) {
            error = 'No se pudo conectar con el servidor.';
        }
        
        submitting = false;
    }

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
    <a href="/venues" class="text-lg text-bold text-cold-light"><ArrowLeft/></a>
</div>
{#if !isAuthenticated}
  <div class="mt-8 p-6 bg-yellow-100 text-yellow-800 rounded-md text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para crear un local.
  </div>
{:else}
  {#if !success && !error}
    <form on:submit|preventDefault={handleSubmit}>
        <div class="flex flex-col w-3/4 p-5 mb-4">
            <label for="name" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Nombre del Local</label>
            <input id="name" type="text" bind:value={name} required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} />
        
            <label for="address" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 50 }}>Dirección</label>
            <input id="address" type="text" bind:value={address} required class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 50 }} />
        
            <label for="contact_name" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 100 }}>Persona de contacto</label>
            <input id="contact_name" type="text" bind:value={contactName} required class="p-2 border rounded"  in:fly={{ y: -30, duration: 400, delay: 100 }} />

            <label for="contact" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 150 }}>Info de contacto</label>
            <input id="contact" type="text" bind:value={contact} required class="p-2 border rounded" placeholder="telefono, correo, instagram" in:fly={{ y: -30, duration: 400, delay: 150 }}/>
            
            <label for="venue_type" class="mb-1" in:fly={{ y: -30, duration: 400, delay: 200 }}>Tipo de Local</label>
            <select id="venue_type" bind:value={selectedVenueType} class="p-2 border rounded" in:fly={{ y: -30, duration: 400, delay: 200 }}>
                {#each venueTypes as type}
                    <option value={type.id}>{type.name}</option>
                {/each}
            </select>

            <div class="flex items-center mb-4" in:fly={{ y: -30, duration: 400, delay: 250 }}>
                <input id="allows_parties" type="checkbox" bind:checked={allowsParties} class="mr-2" />
                <label for="allows_parties" class="cursor-pointer">Permite fiestas</label>
            </div>

            <div class="flex items-center mb-4" in:fly={{ y: -30, duration: 400, delay: 300 }}>
                <input id="allows_rehearsals" type="checkbox" bind:checked={allowsRehearsals} class="mr-2" />
                <label for="allows_rehearsals" class="cursor-pointer">Permite ensayos</label>
            </div>
        </div>
        
        <button class="bg-cold-base text-white rounded mx-6 p-4 px-6" type="submit" disabled={submitting}>
            {submitting ? 'Creando...' : 'Crear Local'}
        </button>
    </form>
  {/if}
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nuevo Local Creado!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
  {/if}
{/if}