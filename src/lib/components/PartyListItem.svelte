<script lang="ts">
  import { MapPin, ChevronRight } from 'lucide-svelte';
  import StatusBadge from './StatusBadge.svelte';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';
  export let party: any;
  export let venueName: string;
  export let showStatus = false;
</script>
<a href={`/parties/${party.id}`} class="block">
  <li class="flex flex-row bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-2">
    <div class="grow">
      <div class="flex flex-row items-center gap-2 flex-wrap">
        <div class="text-2xl text-yellow">{party.title}</div>
        {#if showStatus && party.status}<StatusBadge status={party.status} />{/if}
      </div>
      {#if party.description}
        <div class="text-sm text-white">{party.description}</div>
      {/if}
      <div class="text-sm text-white">{dayjs(party.date).locale('es').format('ddd D [de] MMMM, YYYY')}</div>
      <div class="text-sm text-cold-light"><MapPin class="inline-block mr-1" size="15" stroke-width="4"/>{venueName}</div>
    </div>
    <div class="place-content-center"><ChevronRight class="inline-block text-yellow" size="40" stroke-width="8" /></div>
  </li>
</a>
