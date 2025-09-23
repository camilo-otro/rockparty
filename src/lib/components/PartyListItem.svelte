<script lang="ts">
  import { MapPin } from 'lucide-svelte';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';
  export let party: any;
  export let venueName: string;
</script>
<a href={`/parties/${party.id}`} class="block">
  <li class="bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-2">
    <div class="text-2xl text-yellow">{party.title}</div>
    {#if party.description}
      <div class="text-sm text-white">{party.description}</div>
    {/if}
  <div class="text-sm text-white">{dayjs(party.date).locale('es').format('ddd D [de] MMMM, YYYY')}</div>
    <div class="text-sm text-cold-light"><MapPin class="inline-block mr-1" size="15" stroke-width="4"/>{venueName}</div>
  </li>
</a>
