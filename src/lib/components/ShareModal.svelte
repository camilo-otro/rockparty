<script lang="ts">
  export let url: string;
  export let title: string;
  import { createEventDispatcher } from 'svelte';
  const dispatch = createEventDispatcher();
  let copied = false;

  function copyUrl() {
    navigator.clipboard.writeText(url).then(() => {
      copied = true;
      setTimeout(() => copied = false, 2000);
    });
  }

  function close() {
    dispatch('close');
  }
</script>

<div class="fixed inset-0 bg-black bg-opacity-40 flex items-center justify-center z-50">
  <div class="bg-white rounded shadow-lg p-6 w-full max-w-sm relative">
    <button class="absolute top-2 right-2 text-gray-500 hover:text-gray-700" on:click={close} title="Cerrar">✕</button>
    <h3 class="text-lg font-bold mb-2">Compartir: {title}</h3>
    <div class="mb-4">
      <input type="text" value={url} readonly class="w-full p-2 border rounded bg-gray-100 text-gray-700" />
    </div>
    <button class="bg-blue-600 text-white rounded px-4 py-2 w-full" on:click={copyUrl}>
      {#if copied}
        ¡Copiado!
      {:else}
        Copiar enlace
      {/if}
    </button>
  </div>
</div>
