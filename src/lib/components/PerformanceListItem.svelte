<script lang="ts">
  export let title;
  export let artist;
  export let key: string | undefined = undefined;
  export let performers: any[] = []; // Array of { instrument_id, user_id, user_avatar }
  
  // Default instruments with their IDs and icon paths
  const defaultInstruments = [
    { id: 1, name: 'Singer', icon: '/images/microphone.svg' },
    { id: 2, name: 'Lead Guitar', icon: '/images/guitar.svg' },
    { id: 3, name: 'Rhythm Guitar', icon: '/images/guitar.svg' },
    { id: 4, name: 'Bass', icon: '/images/bass.svg' },
    { id: 5, name: 'Keyboard', icon: '/images/keyboard.svg' },
    { id: 6, name: 'Drums', icon: '/images/drums.svg' }
  ];
  
  function getPerformerForInstrument(instrumentId: number) {
    return performers.find(p => p.instrument_id === instrumentId);
  }
  
  // Separate available and filled instruments. NB: reference `performers`
  // directly (not via getPerformerForInstrument) so Svelte's legacy reactivity
  // tracks it as a dependency and these recompute when the prop changes.
  $: availableInstruments = defaultInstruments.filter(instrument => !performers.some(p => p.instrument_id === instrument.id));
  $: filledInstruments = defaultInstruments.filter(instrument => performers.some(p => p.instrument_id === instrument.id));
</script>

<h4 class="text-lg text-yellow font-medium mb-1">{title}</h4>
<div class="mb-1 flex flex-row justify-between items-start">
  <div class="flex flex-col">
    <span class="text-md">{artist}</span>
    {#if key}
      <div class="text-white text-sm">Tonalidad: {key}</div>
    {/if}
  </div>
  <div class="flex flex-row -space-x-2 ml-2 self-end">
    {#each availableInstruments as instrument, index}
      <img 
        src={instrument.icon} 
        alt={instrument.name} 
        class="w-6 h-6 opacity-50 bg-base-900 rounded-full p-0.5"
        style="z-index: {index + 1}"
        title={`${instrument.name} - Available`}
      />
    {/each}
    {#each filledInstruments as instrument, index}
      {@const performer = getPerformerForInstrument(instrument.id)}
      <img 
        src={performer.user_avatar || '/images/avatar-default.svg'} 
        alt="Performer" 
        class="w-6 h-6 rounded-full border border-cold-base bg-base-900"
        style="z-index: {availableInstruments.length + index + 1}"
        title={instrument.name}
      />
    {/each}
  </div>
</div>
