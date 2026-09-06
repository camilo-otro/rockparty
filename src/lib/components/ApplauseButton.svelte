<!-- Applause (#38). One clap per person per target, toggleable — a mis-tap should
     be correctable, and un-clapping can only ever lower a tally.

     Deliberately undramatic: no burst animation, no realtime ticking. The point
     is to register appreciation and get the phone back in a pocket (principle 1
     in docs/specs/applause.md). -->
<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { Hand } from 'lucide-svelte';

  export let count = 0;
  export let clapped = false;
  /** Window closed, or the viewer wasn't there — show the tally, offer no action. */
  export let readOnly = false;
  export let busy = false;
  export let size: 'sm' | 'md' = 'sm';
  /** What is being applauded, for the accessible label ("Aplaudir a Even Flow"). */
  export let label = '';

  const dispatch = createEventDispatcher();
  $: pad = size === 'md' ? 'px-3 py-1.5 text-sm' : 'px-2 py-1 text-xs';
  $: icon = size === 'md' ? 16 : 14;
</script>

{#if readOnly}
  <!-- Still worth showing what the room thought, just not clickable. -->
  <span class="inline-flex items-center gap-1.5 rounded-full border border-cold-light/20 text-cold-light/60 {pad}"
        title={count === 1 ? '1 aplauso' : count + ' aplausos'}>
    <Hand size={icon} />
    {#if count}{count}{/if}
  </span>
{:else}
  <button type="button" on:click|stopPropagation|preventDefault={() => dispatch('toggle')} disabled={busy}
          aria-pressed={clapped}
          aria-label={(clapped ? 'Quitar aplauso' : 'Aplaudir') + (label ? ' — ' + label : '')}
          title={clapped ? 'Quitar aplauso' : 'Aplaudir'}
          class="inline-flex items-center gap-1.5 rounded-full border transition disabled:opacity-50 {pad}
                 {clapped
                   ? 'border-yellow text-yellow bg-yellow/10'
                   : 'border-cold-light/40 text-cold-light hover:border-cold-light hover:text-white'}">
    <Hand size={icon} />
    {#if count}{count}{/if}
  </button>
{/if}
