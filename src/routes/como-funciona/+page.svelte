<script lang="ts">
  import { ChevronLeft } from 'lucide-svelte';

  const steps = [
    {
      title: 'Encuentra un toque',
      body: 'Explora los próximos toques y los locales cerca de ti desde la página principal.'
    },
    {
      title: 'Súmate o crea el tuyo',
      body: 'Únete a un toque existente o planea uno nuevo en el local que prefieras.'
    },
    {
      title: 'Arma el setlist',
      body: 'Propón canciones y apúntate para tocarlas con tu instrumento junto a otros músicos.'
    },
    {
      title: 'Sube al escenario',
      body: 'El día del evento sigue el orden en vivo, toca y disfruta el show.'
    }
  ];
</script>

<div class="max-w-2xl mx-auto">
  <div class="flex flex-row items-center">
    <a href="/" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft />VOLVER</a>
  </div>
  <section class="mx-4">
    <h2 class="text-3xl text-white m-4 mb-2">CÓMO FUNCIONA</h2>
    <p class="text-cold-light mx-4 mb-6">
      Rock the House conecta a músicos para organizar toques: encuentra un evento,
      súmate al setlist junto a otros músicos y sube al escenario.
    </p>
    <ol class="flex flex-col gap-[1px] rounded-lg overflow-clip">
      {#each steps as step, i}
        <li class="bg-base-900 px-4 py-4 flex flex-row gap-4 items-start">
          <span class="text-3xl text-yellow leading-none w-8 shrink-0 text-center">{i + 1}</span>
          <div>
            <div class="text-lg text-white">{step.title}</div>
            <div class="text-cold-light">{step.body}</div>
          </div>
        </li>
      {/each}
    </ol>
  </section>
  <div class="flex justify-center p-4">
    <a class="text-center bg-cold-base text-white w-2/3 p-4 rounded-lg" href="/parties/create">Planea un toque</a>
  </div>
</div>
