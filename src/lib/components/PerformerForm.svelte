<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  export let submitting = false;
  export let success = false;
  export let error = '';
  export let initialEmail = '';
  export let initialNickname = '';
  export let initialAvatarUrl = '';

  const dispatch = createEventDispatcher();

  let email = initialEmail;
  let nickname = initialNickname;
  let avatarUrl = initialAvatarUrl;

  function handleSubmit() {
    if (!nickname || !email) {
      dispatch('error', 'All fields are required.');
      return;
    }
    dispatch('submit', { nickname, email, avatarUrl });
  }
</script>
<form on:submit|preventDefault={handleSubmit}>
  <div class="flex flex-col w-3/4 p-5 mb-4">
    <label for="email" class="mb-1">Email</label>
    <input id="email" type="text" bind:value={email} readonly class="p-2 bg-base-900 border rounded-lg pointer-events-none" />
    <label for="nickname" class="mb-1">Nickname</label>
    <input id="nickname" type="text" bind:value={nickname} required class="p-2 border rounded-lg" />
    <input type="hidden" bind:value={avatarUrl} />
  </div>
  <button class="bg-cold-base text-white text-sm rounded-full mx-6 p-2 px-6" type="submit" disabled={submitting}>
    {submitting ? 'Creando...' : 'Guardar'}
  </button>
</form>
