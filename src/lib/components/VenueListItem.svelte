<script lang="ts">
  export let venue: any;
</script>
<a href={`/venues/${venue.id}`} class="block">
  <li class="bg-base-900 cursor-pointer hover:bg-base-950 transition px-4 py-2">
    <div class="flex flex-row items-center gap-2 flex-wrap">
      <div class="text-2xl text-yellow">{venue.name}</div>
      {#if venue.is_test}<span class="text-[0.6rem] uppercase tracking-wide px-2 py-0.5 rounded-full border border-warm-base text-warm-base">Prueba</span>{/if}
    </div>
    {#if venue.description}
      <div class="text-sm text-white">{venue.description}</div>
    {/if}
    <div class="flex flex-row width-full justify-between">
        <div class="text-sm text-white">{venue.address}</div>
        <div class="text-sm text-cold-light">{venue.count ? `${venue.count} fiestas próximas` : ''}</div>
    </div>
  </li>
</a>
