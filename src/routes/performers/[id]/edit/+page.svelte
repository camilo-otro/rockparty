<script lang="ts">
import { onMount } from 'svelte';
import { goto } from '$app/navigation';
import { supabase } from '$lib/supabaseClient';
import PerformerForm from '$lib/components/PerformerForm.svelte';
import { ChevronLeft } from 'lucide-svelte';
import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
import { normalizeText } from '$lib/sanitize';

// 'loading' until auth is definitively known, so we never flash the
// logged-out gate during the session-restore race.
let authState: 'loading' | 'in' | 'out' = 'loading';
let submitting = false;
let email = '';
let nickname = '';
let avatarUrl = '';
let userId: string | null = null;
let instruments: any[] = [];
let initialInstruments: number[] = [];

onMount(async () => {
  // getSession() awaits session restoration from storage, so this is the
  // definitive auth check (unlike the layout store, which can be briefly null).
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user) {
    authState = 'out';
    return;
  }
  userId = session.user.id;
  email = session.user.email ?? '';

  // Load the profile fields + instrument lookup + current instruments before
  // rendering the form (PerformerForm copies initialInstruments at init).
  const [{ data: prof }, { data: instrData }, { data: mine }] = await Promise.all([
    supabase.from('profile').select('nickname, avatar_url').eq('id', userId).single(),
    supabase.from('instrument').select('id, name').order('id'),
    supabase.from('profile_instrument').select('instrument_id').eq('profile_id', userId)
  ]);
  nickname = prof?.nickname ?? '';
  avatarUrl = prof?.avatar_url ?? session.user.user_metadata?.avatar_url ?? '';
  instruments = instrData ?? [];
  initialInstruments = (mine ?? []).map((r: any) => r.instrument_id);
  authState = 'in';
});
</script>

<div class="mb-4 mx-4">
  <a href={userId ? `/performers/${userId}` : '/'} class="text-bold text-cold-light flex items-center gap-2"><ChevronLeft/>VOLVER</a>
  <h2 class="text-yellow text-2xl">EDITAR PERFIL</h2>
</div>

{#if authState === 'loading'}
  <div class="text-white p-6 mx-4">Cargando...</div>
{:else if authState === 'out'}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes iniciar sesión para editar tu perfil.
  </div>
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
          const safeNickname = normalizeText(nickname, 80);
          const safeEmail = normalizeText(email, 254);
          const { error: dbError } = existingProfile
            ? await supabase.from('profile').update({ nickname: safeNickname, avatar_url: finalAvatarUrl, email: safeEmail }).eq('id', uid)
            : await supabase.from('profile').insert({ id: uid, nickname: safeNickname, avatar_url: finalAvatarUrl, email: safeEmail });
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
            setTimeout(() => goto(`/performers/${uid}`), 500);
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
