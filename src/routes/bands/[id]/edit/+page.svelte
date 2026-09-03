<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { supabase } from '$lib/supabaseClient';
  import { user } from '$lib/stores/user';
  import { ChevronLeft } from 'lucide-svelte';
  import BandForm from '$lib/components/BandForm.svelte';
  import { uploadBandAvatar, deleteBandAvatarByUrl } from '$lib/bandAvatar';
  import { reportError, toastError, toastSuccess } from '$lib/stores/toasts';

  const bandId = Number(page.params.id);
  let currentUserId: string | null = null;
  let loading = true;
  let band: any = null;
  let isManager = false;
  let instruments: any[] = [];
  let userOptions: any[] = [];
  let initialMembers: any[] = [];
  let originalMembers: any[] = [];   // snapshot for the save-time diff
  let submitting = false;
  let unsub: () => void;

  onMount(async () => {
    unsub = user.subscribe((u) => { currentUserId = u?.id ?? null; });
    const [{ data: b }, { data: mem }, { data: bmi }, { data: instr }, { data: profiles }] = await Promise.all([
      supabase.from('band').select('id, name, bio, who_can_sign_up, created_by, is_test, avatar_url').eq('id', bandId).maybeSingle(),
      supabase.from('band_member').select('user_id, role, profile ( nickname )').eq('band_id', bandId),
      supabase.from('band_member_instrument').select('user_id, instrument_id').eq('band_id', bandId),
      supabase.from('instrument').select('id, name').order('id'),
      supabase.from('profile').select('id, nickname')
    ]);
    band = b;
    instruments = instr ?? [];
    userOptions = profiles ?? [];
    if (band) {
      const instByUser: Record<string, number[]> = {};
      for (const r of bmi ?? []) (instByUser[r.user_id] ??= []).push(r.instrument_id);
      initialMembers = (mem ?? []).map((m: any) => ({
        user_id: m.user_id,
        nickname: m.profile?.nickname ?? '—',
        role: m.role,
        instruments: instByUser[m.user_id] ?? []
      }));
      originalMembers = initialMembers.map((m) => ({ ...m }));
      isManager = !!currentUserId && (mem ?? []).some((m: any) => m.user_id === currentUserId && m.role === 'manager');
    }
    loading = false;
  });
  onDestroy(() => unsub?.());

  async function saveBand(e: CustomEvent) {
    const { name, bio, whoCanSignUp, isTest, avatarBlob, removeAvatar, members } = e.detail;
    submitting = true;
    try {
      // Avatar: upload new (deleting the old), or clear + delete on remove.
      let avatarUpdate: Record<string, any> = {};
      if (avatarBlob) {
        try { avatarUpdate.avatar_url = await uploadBandAvatar(bandId, avatarBlob, band.avatar_url); }
        catch (err) { reportError(err as any); }
      } else if (removeAvatar && band.avatar_url) {
        await deleteBandAvatarByUrl(band.avatar_url);
        avatarUpdate.avatar_url = null;
      }
      const { error: bErr } = await supabase.from('band')
        .update({ name, bio: bio || null, who_can_sign_up: whoCanSignUp, is_test: isTest, ...avatarUpdate }).eq('id', bandId);
      if (bErr) { reportError(bErr); return; }

      const origIds = new Set(originalMembers.map((m) => m.user_id));
      const formIds = new Set(members.map((m: any) => m.user_id));

      // add / update roles
      const upserts = members.map((m: any) => ({ band_id: bandId, user_id: m.user_id, role: m.role }));
      if (upserts.length) {
        const { error } = await supabase.from('band_member')
          .upsert(upserts, { onConflict: 'band_id,user_id', ignoreDuplicates: false });
        if (error) { reportError(error); return; }
      }
      // remove members dropped from the form (never the creator)
      const toRemove = originalMembers
        .filter((m) => !formIds.has(m.user_id) && m.user_id !== band.created_by)
        .map((m) => m.user_id);
      if (toRemove.length) {
        const { error } = await supabase.from('band_member').delete().eq('band_id', bandId).in('user_id', toRemove);
        if (error) { reportError(error); return; }
      }
      // replace instruments wholesale (small set; simpler + correct)
      await supabase.from('band_member_instrument').delete().eq('band_id', bandId);
      const rows = members.flatMap((m: any) => m.instruments.map((iid: number) => ({ band_id: bandId, user_id: m.user_id, instrument_id: iid })));
      if (rows.length) {
        const { error } = await supabase.from('band_member_instrument')
          .upsert(rows, { onConflict: 'band_id,user_id,instrument_id', ignoreDuplicates: true });
        if (error) { reportError(error); return; }
      }
      toastSuccess('Banda actualizada.');
      goto(`/bands/${bandId}`);
    } catch (err) {
      toastError('No se pudo conectar con el servidor.');
    } finally {
      submitting = false;
    }
  }
</script>

<div class="bg-cold-base p-4 flex items-center gap-2">
  <a href={`/bands/${bandId}`} class="text-cold-light hover:text-white"><ChevronLeft /></a>
  <h2 class="text-white text-2xl">EDITAR BANDA</h2>
</div>

{#if loading}
  <div class="mt-8 p-6 text-white">Cargando…</div>
{:else if !band}
  <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">Esta banda no existe.</div>
{:else if !isManager}
  <div class="mt-8 mx-4 p-6 text-red-500">Solo un manager de la banda puede editarla.</div>
{:else}
  <BandForm
    {instruments}
    {userOptions}
    {currentUserId}
    initialName={band.name}
    initialBio={band.bio ?? ''}
    initialWhoCanSignUp={band.who_can_sign_up}
    initialIsTest={band.is_test}
    initialAvatarUrl={band.avatar_url}
    {initialMembers}
    {submitting}
    submitLabel="Guardar cambios"
    on:submit={saveBand}
    on:error={(e) => toastError(e.detail)}
  />
{/if}
