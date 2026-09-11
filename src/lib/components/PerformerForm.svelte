<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import AvatarCropper from '$lib/components/AvatarCropper.svelte';
  export let submitting = false;
  export let initialEmail = '';
  export let initialNickname = '';
  export let initialAvatarUrl = '';
  export let instruments: any[] = [];
  export let initialInstruments: number[] = [];

  const dispatch = createEventDispatcher();

  let email = initialEmail;
  let nickname = initialNickname;
  let avatarUrl = initialAvatarUrl;
  // Avatar (#96), same contract BandForm uses: the cropper emits a
  // ready-to-upload WebP blob and the PAGE uploads it, since only the page knows
  // the uid and holds the old url. removeAvatar flags clearing an existing one.
  let avatarBlob: Blob | null = null;
  let removeAvatar = false;
  let selectedInstruments: number[] = [...initialInstruments];

  function toggleInstrument(id: number) {
    selectedInstruments = selectedInstruments.includes(id)
      ? selectedInstruments.filter((i) => i !== id)
      : [...selectedInstruments, id];
  }

  function handleSubmit() {
    if (!nickname || !email) {
      dispatch('error', 'Todos los campos son obligatorios.');
      return;
    }
    dispatch('submit', { nickname, email, avatarUrl, avatarBlob, removeAvatar, instruments: selectedInstruments });
  }
</script>
<form on:submit|preventDefault={handleSubmit}>
  <div class="flex flex-col w-full p-4 mb-4 gap-1">
    <label for="email" class="mb-1">Email</label>
    <input id="email" type="text" bind:value={email} readonly class="p-2 bg-base-900 border rounded-lg pointer-events-none" />
    <label for="nickname" class="mb-1 mt-3">Nickname</label>
    <input id="nickname" type="text" bind:value={nickname} required class="p-2 border rounded-lg" />

    <AvatarCropper
      initialUrl={initialAvatarUrl}
      label="Tu foto"
      on:crop={(e) => { avatarBlob = e.detail.blob; removeAvatar = false; }}
      on:remove={() => { avatarBlob = null; removeAvatar = true; }}
      on:error={(e) => dispatch('error', e.detail)}
    />

    <span class="mb-1 mt-4">Instrumentos que tocas</span>
    <div class="flex flex-row flex-wrap gap-2">
      {#each instruments as instrument}
        <button
          type="button"
          on:click={() => toggleInstrument(instrument.id)}
          aria-pressed={selectedInstruments.includes(instrument.id)}
          class="px-3 py-1 rounded-full text-sm transition border {selectedInstruments.includes(instrument.id)
            ? 'bg-cold-base text-white border-cold-base'
            : 'bg-base-900 text-cold-light border-base-900 hover:border-cold-light'}"
        >
          {instrument.name}
        </button>
      {/each}
    </div>
  </div>
  <button class="bg-cold-base text-white text-sm rounded-full mx-4 mb-8 p-2 px-6" type="submit" disabled={submitting}>
    {submitting ? 'Guardando...' : 'Guardar'}
  </button>
</form>
