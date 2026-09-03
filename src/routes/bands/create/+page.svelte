<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { ChevronLeft } from 'lucide-svelte';
  import BandForm from '$lib/components/BandForm.svelte';
  import { uploadBandAvatar } from '$lib/bandAvatar';
  import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';

  let currentUserId: string | null = null;
  let isAuthenticated = false;
  let instruments: any[] = [];
  let userOptions: any[] = [];
  let submitting = false;
  let unsub: () => void;

  onMount(async () => {
    unsub = user.subscribe((u) => { currentUserId = u?.id ?? null; isAuthenticated = !!u?.id; });
    const [{ data: instr }, { data: profiles }] = await Promise.all([
      supabase.from('instrument').select('id, name').order('id'),
      supabase.from('profile').select('id, nickname')
    ]);
    instruments = instr ?? [];
    userOptions = profiles ?? [];
    // The creator is seeded into the roster inside BandForm (off currentUserId).
  });

  function loginWithGoogle() {
    supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: window.location.href } });
  }

  async function createBand(e: CustomEvent) {
    const { name, bio, whoCanSignUp, isTest, avatarBlob, members } = e.detail;
    if (!currentUserId) return;
    submitting = true;
    try {
      const { data: band, error: bandErr } = await supabase
        .from('band')
        .insert({ name, bio: bio || null, who_can_sign_up: whoCanSignUp, is_test: isTest, created_by: currentUserId })
        .select('id')
        .single();
      if (bandErr || !band) { reportError(bandErr ?? new Error('No se pudo crear la banda.')); return; }

      // Members other than the creator (the trigger already added them as manager).
      const others = members.filter((m: any) => m.user_id !== currentUserId);
      if (others.length) {
        const { error: memErr } = await supabase.from('band_member')
          .upsert(others.map((m: any) => ({ band_id: band.id, user_id: m.user_id, role: m.role })),
                  { onConflict: 'band_id,user_id', ignoreDuplicates: false });
        if (memErr) { reportError(memErr); return; }
      }
      // Instruments for everyone (creator included).
      const rows = members.flatMap((m: any) => m.instruments.map((iid: number) => ({ band_id: band.id, user_id: m.user_id, instrument_id: iid })));
      if (rows.length) {
        const { error: insErr } = await supabase.from('band_member_instrument')
          .upsert(rows, { onConflict: 'band_id,user_id,instrument_id', ignoreDuplicates: true });
        if (insErr) { reportError(insErr); return; }
      }
      // Avatar upload needs the band id (path + RLS), so it happens post-insert.
      if (avatarBlob) {
        try {
          const url = await uploadBandAvatar(band.id, avatarBlob);
          await supabase.from('band').update({ avatar_url: url }).eq('id', band.id);
        } catch (err) { reportError(err as any); }
      }
      toastSuccess('¡Banda creada!');
      goto(`/bands/${band.id}`);
    } catch (err) {
      toastError('No se pudo conectar con el servidor.');
    } finally {
      submitting = false;
    }
  }

  import { onDestroy } from 'svelte';
  onDestroy(() => unsub?.());
</script>

<div class="bg-cold-base p-4 flex items-center gap-2">
  <a href="/bands" class="text-cold-light hover:text-white"><ChevronLeft /></a>
  <h2 class="text-white text-2xl">NUEVA BANDA</h2>
</div>

{#if !isAuthenticated}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
    Debes <button type="button" class="text-cold-light underline" on:click={loginWithGoogle}>iniciar sesión</button> para crear una banda.
  </div>
{:else}
  <BandForm
    {instruments}
    {userOptions}
    {currentUserId}
    {submitting}
    submitLabel="Crear banda"
    on:submit={createBand}
    on:error={(e) => toastError(e.detail)}
  />
{/if}
