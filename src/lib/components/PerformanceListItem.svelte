<script lang="ts">
  export let title;
  export let artist;
  export let key = undefined;
  export let status;
</script>

<h4 class="text-lg text-yellow font-medium mb-1">{title}</h4>
<div class="text-sm text-white mb-1 flex flex-row justify-between items-center">
  <span>{artist}</span>
  {#if status !== undefined}
    <span class="ml-2 text-sm text-cold-light px-2 py-1">
      {status === 0 ? 'BUSCANDO MÚSICOS'
        : status === 1 ? 'BUSCANDO CANTANTE'
        : status === 2 ? 'SOLO CANTANTE'
        : ''}
    </span>
  {/if}
</div>
{#if key}
    <div class="mb-1 text-white">Tonalidad: {key}</div>
{/if}
