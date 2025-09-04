<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { get } from 'svelte/store';
    import { user } from '$lib/stores/user';

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

    onMount(async () => {
        unsubscribeUser = user.subscribe(u => {
            isAuthenticated = !!u?.id;
            userId = u?.id ?? null;
        });
    });

    onDestroy(() => {
        if (unsubscribeUser) unsubscribeUser();
    });

    async function handleSubmit() {
        if (!name || !address || !contactName || !contact) {
            error = 'Todos los campos son obligatorios.';
            return;
        }
        
        submitting = true;
        error = '';
        
        try {
            const { supabase } = await import('$lib/supabaseClient');
            const { data, error: dbError } = await supabase
                .from('venue')
                .insert([{ name, address, contact_name: contactName, contact }])
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
<div class="bg-slate-400 p-4 flex-row">
    <h2>AGREGAR NUEVO LOCAL</h2>
    <a href="/venues" class="text-lg text-bold text-slate-700"><ArrowLeft/></a>
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
        </div>
        
        <button class="bg-slate-700 text-slate-200 rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 200 }}>
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