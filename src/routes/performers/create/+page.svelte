<script lang="ts">
    import { ArrowLeft } from 'lucide-svelte';
    import { onMount, onDestroy } from 'svelte';
    import { user } from '$lib/stores/user';
    import { get } from 'svelte/store';
    import { sanitizeString } from '$lib/sanitize';
    import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
    import PerformerForm from '$lib/components/PerformerForm.svelte';

    let submitting = false;
    let email: string = '';
    let authId: string = '';
    let userId: string | null = null;
    let nickname = '';
    let isAuthenticated = false;
    let unsubscribeUser: () => void;
    let avatarUrl = '';

    const userObj = get(user);
    email = userObj?.email ?? '';
    authId = userObj?.id ?? '';
    avatarUrl = userObj?.avatarUrl ?? '';

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
            toastError('Todos los campos son obligatorios.');
            return;
        }
        // Sanitize inputs
        const safeNickname = sanitizeString(nickname);
        const safeAuthId = sanitizeString(authId);
        const safeEmail = sanitizeString(email);
        submitting = true;

        try {
            const { supabase } = await import('$lib/supabaseClient');
            const { data, error: dbError } = await supabase
                .from('profile')
                .insert([{ id: authId, nickname: safeNickname, email: safeEmail }])
                .select();

            if (dbError) {
                reportError(dbError);
            } else {
                toastSuccess('¡Nuevo intérprete creado!');
                setTimeout(() => {
                    window.location.href = '/';
                }, 1000);
            }
        } catch (e) {
            toastError('No se pudo conectar con el servidor.');
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
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para crear un intérprete.
  </div>
{:else}
  <PerformerForm
      submitting={submitting}
      initialEmail={email}
      initialNickname={nickname}
      initialAvatarUrl={avatarUrl}
      on:submit={async (e) => {
        submitting = true;
        const { nickname, email, avatar_url } = e.detail;
        try {
          const { supabase } = await import('$lib/supabaseClient');
          const { data, error: dbError } = await supabase
            .from('profile')
            .insert([{ id: authId, nickname, email, avatar_url }])
            .select();
          if (dbError) {
            reportError(dbError);
          } else {
            toastSuccess('¡Nuevo intérprete creado!');
            setTimeout(() => {
              window.location.href = '/';
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
