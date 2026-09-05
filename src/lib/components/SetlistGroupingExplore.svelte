<!-- Visual exploration (Storybook only): ways to group band-owned songs on a
     setlist so the band lineup isn't repeated on every row. Not wired into the
     app — see the stories for side-by-side comparison. -->
<script lang="ts">
  import { Users } from 'lucide-svelte';

  export let variant: 'current' | 'a' | 'b' | 'c' = 'current';

  const LOS_PRUEBA = { id: 1, name: 'Los Prueba', members: 3 };
  const PULSE = { id: 2, name: 'Pulse', members: 4 };

  // A realistic mix: an open jam, a 3-song band run, another open jam breaking
  // it up, then a 2-song run — so grouping and its edge cases are both visible.
  const songs = [
    { n: 1, title: 'Crossfire', artist: 'Brandon Flowers', band: null },
    { n: 2, title: 'One', artist: 'Metallica', band: LOS_PRUEBA },
    { n: 3, title: 'Enter Sandman', artist: 'Metallica', band: LOS_PRUEBA },
    { n: 4, title: 'Wasteland', artist: '10 Years', band: LOS_PRUEBA },
    { n: 5, title: 'Beautiful Day', artist: 'U2', band: null },
    { n: 6, title: 'Vertigo', artist: 'U2', band: PULSE },
    { n: 7, title: 'Elevation', artist: 'U2', band: PULSE }
  ];

  const GAPS = ['/images/microphone.svg', '/images/guitar.svg', '/images/bass.svg', '/images/keyboard.svg', '/images/drums.svg'];
  const AVATAR = '/images/avatar-default.svg';

  // Consecutive runs by the same band (null band = its own run of one).
  type Run = { band: any; items: typeof songs };
  $: runs = songs.reduce<Run[]>((acc, s) => {
    const last = acc[acc.length - 1];
    if (last && last.band && s.band && last.band.id === s.band.id) last.items.push(s);
    else acc.push({ band: s.band, items: [s] });
    return acc;
  }, []);

  const LABELS = {
    current: ['Actual', 'La banda y su alineación se repiten en cada canción.'],
    a: ['A · Bloque de set', 'Las canciones seguidas de una banda se agrupan bajo una cabecera; la alineación se muestra una vez.'],
    b: ['B · Continuación', 'Filas iguales, pero solo la primera de la banda muestra su identidad; el resto lleva una guía lateral.'],
    c: ['C · Chip compacto', 'Cada fila conserva su identidad, pero la alineación se reduce a un chip de banda.']
  } as const;
</script>

<div class="bg-base-950 text-white font-sans p-4 max-w-[393px]">
  <div class="mb-3">
    <h3 class="text-xl tracking-wide">{LABELS[variant][0]}</h3>
    <p class="text-cold-light text-xs mt-0.5 leading-snug">{LABELS[variant][1]}</p>
  </div>

  <h2 class="text-3xl text-white font-medium tracking-wide mb-2">SETLIST</h2>

  {#if variant === 'current'}
    <!-- Today: every band row repeats the name + the member avatars. -->
    <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
      {#each songs as s}
        <li class="bg-base-900 px-4 py-3 flex items-center gap-3">
          <span class="text-gray-400 text-3xl font-medium w-7 shrink-0">{s.n}</span>
          <div class="flex-1 min-w-0">
            <div class="text-lg text-yellow truncate">{s.title}</div>
            <div class="text-sm text-cold-light truncate">{s.artist}</div>
            {#if s.band}
              <span class="text-xs text-cold-light inline-flex items-center gap-1 mt-0.5">
                <Users size={12} /> {s.band.name}
              </span>
            {/if}
          </div>
          <div class="flex flex-row -space-x-2 shrink-0">
            {#if s.band}
              {#each Array(s.band.members) as _}
                <img src={AVATAR} alt="" class="w-6 h-6 rounded-full border border-cold-base bg-base-900" />
              {/each}
            {:else}
              {#each GAPS as g}
                <img src={g} alt="" class="w-6 h-6 bg-base-900 rounded-full p-0.5 opacity-50" />
              {/each}
            {/if}
          </div>
        </li>
      {/each}
    </ul>

  {:else if variant === 'a'}
    <!-- A: a band's consecutive songs become one "set" block. -->
    <div class="flex flex-col gap-2">
      {#each runs as run}
        {#if run.band}
          <div class="rounded-lg overflow-clip border-l-2 border-cold-base">
            <div class="bg-base-900 px-4 py-2.5 flex items-center gap-3">
              <span class="w-9 h-9 rounded-full bg-base-950 border border-cold-base flex items-center justify-center shrink-0">
                <Users size={16} class="text-cold-light" />
              </span>
              <div class="flex-1 min-w-0">
                <div class="text-white truncate">{run.band.name}</div>
                <div class="text-cold-light text-xs uppercase tracking-wide">{run.items.length} canciones</div>
              </div>
              <div class="flex flex-row -space-x-2 shrink-0">
                {#each Array(run.band.members) as _}
                  <img src={AVATAR} alt="" class="w-6 h-6 rounded-full border border-cold-base bg-base-900" />
                {/each}
              </div>
            </div>
            <div class="flex flex-col gap-[1px] mt-[1px]">
              {#each run.items as s}
                <div class="bg-base-900 px-4 py-2 flex items-baseline gap-3">
                  <span class="text-gray-400 text-xl font-medium w-7 shrink-0">{s.n}</span>
                  <span class="text-yellow truncate">{s.title}</span>
                  <span class="text-sm text-cold-light truncate ml-auto">{s.artist}</span>
                </div>
              {/each}
            </div>
          </div>
        {:else}
          {#each run.items as s}
            <div class="bg-base-900 rounded-lg px-4 py-3 flex items-center gap-3">
              <span class="text-gray-400 text-3xl font-medium w-7 shrink-0">{s.n}</span>
              <div class="flex-1 min-w-0">
                <div class="text-lg text-yellow truncate">{s.title}</div>
                <div class="text-sm text-cold-light truncate">{s.artist}</div>
              </div>
              <div class="flex flex-row -space-x-2 shrink-0">
                {#each GAPS as g}
                  <img src={g} alt="" class="w-6 h-6 bg-base-900 rounded-full p-0.5 opacity-50" />
                {/each}
              </div>
            </div>
          {/each}
        {/if}
      {/each}
    </div>

  {:else if variant === 'b'}
    <!-- B: uniform rows; only the first of a run carries the band identity. -->
    <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
      {#each runs as run}
        {#each run.items as s, i}
          <li class="bg-base-900 px-4 py-3 flex items-center gap-3 {run.band ? 'border-l-2 border-cold-base' : ''}">
            <span class="text-gray-400 text-3xl font-medium w-7 shrink-0">{s.n}</span>
            <div class="flex-1 min-w-0">
              {#if run.band && i === 0}
                <div class="text-xs text-cold-light inline-flex items-center gap-1 mb-0.5">
                  <Users size={12} /> {run.band.name} · {run.items.length} canciones
                </div>
              {/if}
              <div class="text-lg text-yellow truncate">{s.title}</div>
              <div class="text-sm text-cold-light truncate">{s.artist}</div>
            </div>
            <div class="flex flex-row -space-x-2 shrink-0">
              {#if run.band}
                {#if i === 0}
                  {#each Array(run.band.members) as _}
                    <img src={AVATAR} alt="" class="w-6 h-6 rounded-full border border-cold-base bg-base-900" />
                  {/each}
                {/if}
              {:else}
                {#each GAPS as g}
                  <img src={g} alt="" class="w-6 h-6 bg-base-900 rounded-full p-0.5 opacity-50" />
                {/each}
              {/if}
            </div>
          </li>
        {/each}
      {/each}
    </ul>

  {:else}
    <!-- C: no grouping — the member stack collapses to one band chip. -->
    <ul class="flex flex-col gap-[1px] rounded-lg overflow-clip">
      {#each songs as s}
        <li class="bg-base-900 px-4 py-3 flex items-center gap-3">
          <span class="text-gray-400 text-3xl font-medium w-7 shrink-0">{s.n}</span>
          <div class="flex-1 min-w-0">
            <div class="text-lg text-yellow truncate">{s.title}</div>
            <div class="text-sm text-cold-light truncate">{s.artist}</div>
          </div>
          {#if s.band}
            <span class="shrink-0 inline-flex items-center gap-1.5 rounded-full border border-cold-base/60 bg-base-950 pl-1 pr-2.5 py-1">
              <span class="w-5 h-5 rounded-full bg-base-900 flex items-center justify-center">
                <Users size={11} class="text-cold-light" />
              </span>
              <span class="text-xs text-cold-light">{s.band.name}</span>
            </span>
          {:else}
            <div class="flex flex-row -space-x-2 shrink-0">
              {#each GAPS as g}
                <img src={g} alt="" class="w-6 h-6 bg-base-900 rounded-full p-0.5 opacity-50" />
              {/each}
            </div>
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
</div>
