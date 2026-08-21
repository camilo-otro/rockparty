<script lang="ts">
import { onMount } from 'svelte';
import { user } from '$lib/stores/user';
import PerformerForm from '$lib/components/PerformerForm.svelte';
import { ChevronLeft } from 'lucide-svelte';
import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';

let submitting = false;
let isAuthenticated = false;
let email = '';
let nickname = '';
let avatarUrl = '';
let userId: string | null = null;
let unsubscribeUser: () => void;
let previousPage = '/'; // fallback to home
let instruments: any[] = [];
let initialInstruments: number[] = [];
let dataLoaded = false;

onMount(async () => {
  // Store the previous page, fallback to home if no referrer
  previousPage = document.referrer || '/';

  unsubscribeUser = user.subscribe(u => {
    isAuthenticated = !!u?.id;
    userId = u?.id ?? null;
    email = u?.email ?? '';
    nickname = u?.nickname ?? '';
    avatarUrl = u?.avatarUrl ?? '';
  });

  // Load the instrument lookup + this performer's current instruments before
  // rendering the form (PerformerForm copies initialInstruments at init).
  const { supabase } = await import('$lib/supabaseClient');
  const { data: instrData } = await supabase.from('instrument').select('id, name').order('id');
  instruments = instrData ?? [];
  if (userId) {
    const { data: mine } = await supabase.from('profile_instrument').select('instrument_id').eq('profile_id', userId);
    initialInstruments = (mine ?? []).map((r: any) => r.instrument_id);
  }
  dataLoaded = true;
});
</script>

<div class="mb-4 mx-4">
  <a href="/performers" class="text-bold text-cold-light flex items-center gap-2"><ChevronLeft/>VOLVER</a>
  <h2 class="text-yellow text-2xl">EDITAR PERFIL</h2>
</div>

{#if !isAuthenticated}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes iniciar sesión para editar tu perfil.
  </div>
{:else if !dataLoaded}
  <div class="text-white p-6 mx-4">Cargando...</div>
{:else}
  <PerformerForm
    submitting={submitting}
    initialEmail={email}
    initialNickname={nickname}
    initialAvatarUrl={avatarUrl}
    instruments={instruments}
    initialInstruments={initialInstruments}
    on:submit={async (e) => {
      submitting = true;
      const { nickname, email, avatarUrl, instruments: selected } = e.detail;
      const uid = userId;
      if (!uid) { toastError('No autenticado.'); submitting = false; return; }
      try {
        const { supabase } = await import('$lib/supabaseClient');

        // If avatarUrl is empty, try to get it from Google auth
        let finalAvatarUrl = avatarUrl;
        if (!avatarUrl || avatarUrl.trim() === '') {
          const { data: { user: authUser } } = await supabase.auth.getUser();
          if (authUser?.user_metadata?.avatar_url) {
            finalAvatarUrl = authUser.user_metadata.avatar_url;
          }
        }

        // Check if profile exists
        const { data: existingProfile, error: fetchError } = await supabase
          .from('profile')
          .select('id')
          .eq('id', uid)
          .single();

        if (fetchError && fetchError.code !== 'PGRST116') {
          // PGRST116 is "not found" error, other errors are actual problems
          reportError(fetchError);
        } else {
          // Update if the profile exists, otherwise insert a new one.
          const { error: dbError } = existingProfile
            ? await supabase.from('profile').update({ nickname, avatar_url: finalAvatarUrl, email }).eq('id', uid)
            : await supabase.from('profile').insert({ id: uid, nickname, avatar_url: finalAvatarUrl, email });
          if (dbError) {
            reportError(dbError);
          } else {
            // Sync the performer's instruments (add new, remove dropped).
            const initialSet = new Set(initialInstruments);
            const selectedSet = new Set(selected);
            const toAdd = (selected as number[]).filter((i) => !initialSet.has(i));
            const toRemove = initialInstruments.filter((i) => !selectedSet.has(i));
            if (toRemove.length) {
              await supabase.from('profile_instrument').delete().eq('profile_id', uid).in('instrument_id', toRemove);
            }
            if (toAdd.length) {
              await supabase.from('profile_instrument').insert(toAdd.map((i) => ({ profile_id: uid, instrument_id: i })));
            }
            toastSuccess('¡Perfil actualizado!');
            setTimeout(() => {
              window.location.href = previousPage;
            }, 500);
          }
        }
      } catch (e) {
        toastError('No se pudo conectar con el servidor.');
      }
      submitting = false;
    }}
    on:error={(e) => toastError(e.detail)}
  />
{/if}
