<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import { sanitizeString } from '$lib/sanitize';

    let submitting = false;
    let email: string = '';
    let authId: string = '';
    let userId: string | null = null;
    let nickname = '';
    let success = false;
    let error = '';
    let isAuthenticated = false;
    let unsubscribeUser: () => void;

    const userObj = get(user);
    email = userObj?.email ?? '';
    authId = userObj?.id ?? '';

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
        if (!nickname || !authId || !email) {
            error = 'All fields are required.';
            return;
        }
        // Sanitize inputs
        const safeNickname = sanitizeString(nickname);
        const safeAuthId = sanitizeString(authId);
        const safeEmail = sanitizeString(email);
        submitting = true;
        error = '';
        
        try {
            const { supabase } = await import('$lib/supabaseClient');
            const { data, error: dbError } = await supabase
                .from('profile')
                .insert([{ nickname: safeNickname, email: safeEmail }])
                .select();
                
            if (dbError) {
                error = `Database error: ${dbError.message}`;
            } else {
                success = true;
                setTimeout(() => {
                    window.location.href = '/';
                }, 1000);
            }
        } catch (e) {
            error = 'Could not connect to the server.';
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
    <h2 class="text-white text-2xl">AGREGAR NUEVO INTÉRPRETE</h2>
    <a href="/performers" class="text-lg text-bold text-cold-light"><ArrowLeft/></a>
</div>
{#if !isAuthenticated}
  <div class="mt-8 p-6 bg-yellow-100 text-yellow-800 rounded-md text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para crear un intérprete.
  </div>
{:else}
  {#if !success && !error}
    <form on:submit|preventDefault={handleSubmit}>
        <div class="flex flex-col w-3/4 p-5 mb-4">
            <label for="email" class="mb-1">Email</label>
            <input id="email" type="text" value={email} readonly class="p-2 border rounded bg-gray-100 text-gray-600" />
            <label for="nickname" class="mb-1" in:fly={{ y: -30, duration: 400 }}>Nickname</label>
            <input id="nickname" type="text" bind:value={nickname} required class="p-2 border rounded" in:fly={{ y: -30, duration: 400 }} />
        </div>
        <button class="bg-cold-base text-white rounded mx-6 p-4 px-6" type="submit" disabled={submitting} in:fly={{ y: -30, duration: 400, delay: 100 }}>
            {submitting ? 'Creando...' : 'Crear Intérprete'}
        </button>
    </form>
  {/if}
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Nuevo Intérprete Creado!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-md text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
  {/if}
{/if}
