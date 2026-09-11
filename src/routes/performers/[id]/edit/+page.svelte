<script lang="ts">
import { onMount } from 'svelte';
import { goto } from '$app/navigation';
import { supabase } from '$lib/supabaseClient';
import PerformerForm from '$lib/components/PerformerForm.svelte';
import { ChevronLeft } from 'lucide-svelte';
import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';
import { normalizeText } from '$lib/sanitize';
import { uploadProfileAvatar, deleteProfileAvatarByUrl } from '$lib/profileAvatar';
import { page } from '$app/state';

// Where to go once the profile is saved. The root layout sends profile-less
// users here with ?next=<where they were headed>, so a deep link survives the
// detour instead of dumping them on their own profile (#79).
//
// Only same-origin destinations are honoured — this value rides in a URL anyone
// can hand you, so it is an open-redirect vector.
//
// Do NOT string-match for this. A `startsWith('/') && !startsWith('//')` guard
// looks right and is not: the URL spec treats a backslash as a path separator
// for http(s), so `/\evil.com` passes that test and resolves to
// `http://evil.com/`. Verified in a browser. Let the URL parser normalise it and
// compare origins, which is the only thing that actually decides the question.
function afterSaveTarget(uid: string) {
  const next = page.url.searchParams.get('next');
  if (next) {
    try {
      const resolved = new URL(next, window.location.origin);
      if (resolved.origin === window.location.origin) {
        return resolved.pathname + resolved.search + resolved.hash;
      }
    } catch {
      /* unparseable — fall through to the profile */
    }
  }
  return `/performers/${uid}`;
}

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
      const { nickname, email, avatarUrl, avatarBlob, removeAvatar, instruments: selected } = e.detail;
      const uid = userId;
      if (!uid) { toastError('No autenticado.'); submitting = false; return; }
      try {
        // Avatar (#96). The column holds EITHER a Google CDN url (the signup
        // default) or one of ours in profile-avatars, so every branch here has
        // to end with a usable url rather than assuming which kind it started as.
        let finalAvatarUrl = avatarUrl;
        const googleAvatar = async () => {
          const { data: { user: authUser } } = await supabase.auth.getUser();
          return authUser?.user_metadata?.avatar_url ?? '';
        };

        if (avatarBlob) {
          // Uploaded here, not in the form: only the page knows the uid, and the
          // old url has to be passed so the previous object is cleaned up.
          // Passing a Google url is harmless — it is outside the bucket, so
          // deleteAvatarByUrl no-ops on it.
          try {
            finalAvatarUrl = await uploadProfileAvatar(uid, avatarBlob, avatarUrl || null);
          } catch (err) {
            reportError(err);
            submitting = false;
            return;   // never save a profile claiming a photo that is not there
          }
        } else if (removeAvatar) {
          // "Quitar la foto" falls back to the GOOGLE picture, not a blank
          // silhouette — you can always get your original back, and the app
          // never has to render an empty avatar.
          if (avatarUrl) await deleteProfileAvatarByUrl(avatarUrl);
          finalAvatarUrl = await googleAvatar();
        } else if (!avatarUrl || avatarUrl.trim() === '') {
          finalAvatarUrl = await googleAvatar();
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
            setTimeout(() => goto(afterSaveTarget(uid)), 500);
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
