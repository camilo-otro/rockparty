<script lang="ts">
  import { Users } from 'lucide-svelte';

  export let title;
  export let artist;
  export let key: string | undefined = undefined;
  export let performers: any[] = []; // Array of { instrument_id, user_id, user_avatar }
  // Instrument ids the viewer plays (#32) — open slots matching these are
  // highlighted as "you could fill this" instead of dimmed.
  export let highlightInstrumentIds: number[] = [];
  // Band-owned song (#74): render the band + its lineup, no instrument gaps.
  export let band: { name: string; pending?: boolean } | null = null;
  export let lineup: any[] = []; // for a band: unique members [{ user_id, user_avatar }]
  
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
    {#if band}
      <span class="text-xs text-cold-light inline-flex items-center gap-1 mt-0.5">
        <Users size={12} /> {band.name}{#if band.pending} · <span class="text-yellow">pendiente</span>{/if}
      </span>
    {/if}
  </div>
  {#if band}
    <!-- Band lineup: the members, no open-slot gaps. -->
    <div class="flex flex-row -space-x-2 ml-2 self-end {band.pending ? 'opacity-60' : ''}">
      {#each lineup as member, index}
        <img
          src={member.user_avatar || '/images/avatar-default.svg'}
          alt="Integrante"
          class="w-6 h-6 rounded-full border border-cold-base bg-base-900"
          style="z-index: {index + 1}"
        />
      {/each}
    </div>
  {:else}
    <div class="flex flex-row -space-x-2 ml-2 self-end">
      {#each availableInstruments as instrument, index}
        {@const mine = highlightInstrumentIds.includes(instrument.id)}
        <img
          src={instrument.icon}
          alt={instrument.name}
          class="w-6 h-6 bg-base-900 rounded-full p-0.5 {mine ? 'opacity-100 ring-2 ring-yellow' : 'opacity-50'}"
          style="z-index: {index + 1}"
          title={mine ? `${instrument.name} — ¡puedes tocar!` : `${instrument.name} - Available`}
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
  {/if}
</div>
