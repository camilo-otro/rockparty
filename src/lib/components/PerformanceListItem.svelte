<script lang="ts">
  export let title;
  export let artist;
  export let key = undefined;
  export let performers: any[] = []; // Array of { instrument_id, user_id, user_avatar }
  
  // Default instruments with their IDs and icon paths
  const defaultInstruments = [
    { id: 1, name: 'Singer', icon: '/static/images/microphone.svg' },
    { id: 2, name: 'Lead Guitar', icon: '/static/images/guitar.svg' },
    { id: 3, name: 'Rhythm Guitar', icon: '/static/images/guitar.svg' },
    { id: 4, name: 'Bass', icon: '/static/images/bass.svg' },
    { id: 5, name: 'Keyboard', icon: '/static/images/keyboard.svg' },
    { id: 6, name: 'Drums', icon: '/static/images/drums.svg' }
  ];
  
  function getPerformerForInstrument(instrumentId: number) {
    return performers.find(p => p.instrument_id === instrumentId);
  }
  
  // Separate available and filled instruments
  $: availableInstruments = defaultInstruments.filter(instrument => !getPerformerForInstrument(instrument.id));
  $: filledInstruments = defaultInstruments.filter(instrument => getPerformerForInstrument(instrument.id));
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
    {#each availableInstruments as instrument}
      <img 
        src={instrument.icon} 
        alt={instrument.name} 
        class="w-6 h-6 opacity-50 bg-base-900 rounded-full p-0.5"
        title={`${instrument.name} - Available`}
      />
    {/each}
    {#each filledInstruments as instrument}
      {@const performer = getPerformerForInstrument(instrument.id)}
      <img 
        src={performer.user_avatar || '/images/avatar-default.svg'} 
        alt="Performer" 
        class="w-6 h-6 rounded-full border border-cold-base bg-base-900"
        title={instrument.name}
      />
    {/each}
  </div>
</div>
