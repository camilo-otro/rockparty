<script lang="ts">
    import { ChevronLeft } from 'lucide-svelte';
    import { fly } from 'svelte/transition';
    import { onMount, onDestroy } from 'svelte';
    import { supabase } from '$lib/supabaseClient';
    import { user } from '$lib/stores/user';
    import PartyForm from '$lib/components/PartyForm.svelte';
    let submitting = false;
    let venues: any[] = [];
    let loadingVenues = true;
    let errorVenues: string | null = null;
    let userId: string | null = null;
    let date = '';
    let selectedVenue = '';
    let success = false;
    let error = '';
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
<div class="bg-cold-base p-4 flex-row">
    <h2 class="text-white text-2xl">AGREGAR NUEVA FIESTA</h2>
    <a href="/parties" class="text-lg text-bold text-cold-light"><ChevronLeft/></a>
</div>
{#if !isAuthenticated}
  <div class="mt-8 p-6 bg-yellow-100 text-yellow-800 rounded-lg text-center">
    Debes <a href="#" class="text-blue-600 underline" on:click={loginWithGoogle}>iniciar sesión</a> para crear una fiesta.
  </div>
{:else}
  {#if !success && !error}
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
      success={success}
      error={error}
      userId={userId}
      isAuthenticated={isAuthenticated}
      on:submit={async (e) => {
        submitting = true;
        error = '';
        const { title, description, date, venue, admins } = e.detail;
        try {
          const { data, error: dbError } = await supabase
            .from('party')
            .insert([{ date, venue, created_by: userId, title, description }])
            .select();
          if (dbError) {
            error = `Database error: ${dbError.message}`;
          } else {
            // Add party_admins
            if (data && data.length > 0 && admins && admins.length > 0) {
              await supabase.from('party_admin').insert(admins.map((a: string) => ({ party_id: data[0].id, user_id: a })));
            }
            success = true;
            setTimeout(() => {
              window.location.href = '/parties';
            }, 1000);
          }
        } catch (e) {
          error = 'Could not connect to the server.';
        }
        submitting = false;
      }}
      on:error={(e) => error = e.detail}
    />
  {/if}
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Nueva Fiesta Creada!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-lg text-center" in:fly={{ y: -20, duration: 400 }}>
    Error: {error}
    </div>
  {/if}
{/if}
