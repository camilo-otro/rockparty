<script lang="ts">
import { onMount } from 'svelte';
import { user } from '$lib/stores/user';
import PerformerForm from '$lib/components/PerformerForm.svelte';
import { ChevronLeft } from 'lucide-svelte';

let submitting = false;
let success = false;
let error = '';
let isAuthenticated = false;
let email = '';
let nickname = '';
let avatarUrl = '';
let userId: string | null = null;
let unsubscribeUser: () => void;
let previousPage = '/'; // fallback to home

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
});

function handleBack() {
  window.location.href = previousPage;
}
</script>

<div class="mb-4 mx-4">
  <a href="/performers" class="text-bold text-cold-light flex items-center gap-2"><ChevronLeft/>VOLVER</a>
  <h2 class="text-yellow text-2xl">EDITAR PERFIL</h2>
</div>
  
{#if !isAuthenticated}
  <div class="mt-8 p-6 bg-yellow-100 text-yellow-800 rounded-lg text-center">
    Debes iniciar sesión para editar tu perfil.
  </div>
{:else}
  <PerformerForm
    submitting={submitting}
    success={success}
    error={error}
    initialEmail={email}
    initialNickname={nickname}
    initialAvatarUrl={avatarUrl}
    on:submit={async (e) => {
      submitting = true;
      error = '';
      const { nickname, email, avatarUrl } = e.detail;
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
          .eq('id', userId)
          .single();
        
        if (fetchError && fetchError.code !== 'PGRST116') {
          // PGRST116 is "not found" error, other errors are actual problems
          error = `Database error: ${fetchError.message}`;
        } else if (existingProfile) {
          // Profile exists, update it
          const { error: dbError } = await supabase
            .from('profile')
            .update({ nickname, avatar_url: finalAvatarUrl, email })
            .eq('id', userId);
          if (dbError) {
            error = `Database error: ${dbError.message}`;
          } else {
            success = true;
            setTimeout(() => {
              window.location.href = previousPage;
            }, 500);
          }
        } else {
          // Profile doesn't exist, insert new one
          const { error: dbError } = await supabase
            .from('profile')
            .insert({ id: userId, nickname, avatar_url: finalAvatarUrl, email });
          if (dbError) {
            error = `Database error: ${dbError.message}`;
          } else {
            success = true;
            setTimeout(() => {
              window.location.href = previousPage;
            }, 500);
          }
        }
      } catch (e) {
        error = 'Could not connect to the server.';
      }
      submitting = false;
    }}
    on:error={(e) => error = e.detail}
  />
  {#if success}
    <div class="mt-4 p-3 bg-green-100 text-green-800 rounded-lg text-center">
      Perfil actualizado!
    </div>
  {/if}
  {#if error}
    <div class="mt-4 p-3 bg-red-100 text-red-800 rounded-lg text-center">
      Error: {error}
    </div>
  {/if}
{/if}
