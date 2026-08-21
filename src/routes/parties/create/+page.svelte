<script lang="ts">
    import { ChevronLeft } from 'lucide-svelte';
    import { onMount, onDestroy } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { user } from '$lib/stores/user';
    import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
    import PartyForm from '$lib/components/PartyForm.svelte';
    let submitting = false;
    let venues: any[] = [];
    let loadingVenues = true;
    let errorVenues: string | null = null;
    let userId: string | null = null;
    let date = '';
    let selectedVenue = '';
    let isAuthenticated = false;
    let unsubscribeUser: () => void;
    let title = '';
    let description = '';

    onMount(async () => {
      unsubscribeUser = user.subscribe(u => {
        isAuthenticated = !!u?.id;
        userId = u?.id ?? null;
      });
        const { data, error } = await supabase.from('venue').select('id, name');
        if (error) {
            errorVenues = error.message;
        } else {
            venues = data ?? [];
        }
        loadingVenues = false;
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
<a href="/parties" class="text-bold text-cold-light flex flex-row px-4"><ChevronLeft />VOLVER</a>
<h2 class="text-yellow text-2xl px-5 py-2">CREAR UN TOQUE</h2>
{#if !isAuthenticated}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para crear un toque.
  </div>
{:else}
  <PartyForm
    venues={venues}
    loadingVenues={loadingVenues}
    errorVenues={errorVenues}
    initialTitle={title}
    initialDescription={description}
    initialDate={date}
    initialVenue={selectedVenue}
    initialAdmins={[]}
    submitting={submitting}
    userId={userId}
    isAuthenticated={isAuthenticated}
    on:submit={async (e) => {
      submitting = true;
      const { title, description, date, venue, admins } = e.detail;
      try {
        const { data, error: dbError } = await supabase
          .from('party')
          .insert([{ date, venue, created_by: userId, title, description }])
          .select();
        if (dbError) {
          reportError(dbError);
        } else {
          const newId = data && data.length > 0 ? data[0].id : null;
          // Add party_admins
          if (newId && admins && admins.length > 0) {
            await supabase.from('party_admin').insert(admins.map((a: string) => ({ party_id: newId, user_id: a })));
          }
          toastSuccess('Borrador creado — revísalo y publícalo.');
          setTimeout(() => {
            window.location.href = newId ? `/parties/${newId}` : '/parties';
          }, 1000);
        }
      } catch (e) {
        toastError('No se pudo conectar al servidor.');
      }
      submitting = false;
    }}
    on:error={(e) => toastError(e.detail)}
  />
{/if}
