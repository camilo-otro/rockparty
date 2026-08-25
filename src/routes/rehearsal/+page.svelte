<script lang="ts">
  import { onMount } from 'svelte';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, MapPin, ExternalLink } from 'lucide-svelte';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';
  dayjs.locale('es');

  // 'loading' until auth is known, so we don't flash the logged-out gate (#48).
  let authState: 'loading' | 'in' | 'out' = 'loading';
  // One entry per upcoming toque the user plays in, with the songs they play.
  let toques: {
    party: { id: number; title: string; date: string };
    songs: { perfId: number; title: string; artist: string; key: string | null; link: string | null; instruments: string[] }[];
  }[] = [];

  const UPCOMING = ['confirmed', 'live'];
  const todayStr = dayjs().format('YYYY-MM-DD');

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession();
    if (!session?.user) { authState = 'out'; return; }
    const uid = session.user.id;

    // Songs the user is approved to play.
    const { data: signups } = await supabase
      .from('performance_user').select('performance_id, instrument_id').eq('user_id', uid).eq('status', 'approved');
    const perfIds = [...new Set((signups ?? []).map((s) => s.performance_id))];
    if (!perfIds.length) { authState = 'in'; return; }

    const { data: perfs } = await supabase.from('performance').select('id, song, key, ref_link, party').in('id', perfIds);
    const partyIds = [...new Set((perfs ?? []).map((p) => p.party).filter(Boolean))] as number[];
    const songIds = [...new Set((perfs ?? []).map((p) => p.song).filter(Boolean))] as number[];

    const [{ data: parties }, { data: songs }, { data: instruments }] = await Promise.all([
      supabase.from('party').select('id, title, date, status').in('id', partyIds),
      songIds.length ? supabase.from('song').select('id, title, artist, ref_link').in('id', songIds) : Promise.resolve({ data: [] as any[] }),
      supabase.from('instrument').select('id, name')
    ]);

    const partyById = new Map((parties ?? []).map((p: any) => [p.id, p]));
    const songById = new Map((songs ?? []).map((s: any) => [s.id, s]));
    const instrName = new Map((instruments ?? []).map((i: any) => [i.id, i.name]));

    // Which instruments the user plays on each performance.
    const instrsByPerf: Record<number, string[]> = {};
    for (const s of signups ?? []) {
      const n = instrName.get(s.instrument_id);
      if (n) (instrsByPerf[s.performance_id] ??= []).push(n);
    }

    // Group the user's songs by their upcoming toque.
    const byParty: Record<number, typeof toques[number]> = {};
    for (const perf of perfs ?? []) {
      const party = partyById.get(perf.party);
      if (!party || !UPCOMING.includes(party.status) || (party.date ?? '') < todayStr) continue;
      const song = songById.get(perf.song);
      (byParty[party.id] ??= { party: { id: party.id, title: party.title, date: party.date }, songs: [] }).songs.push({
        perfId: perf.id,
        title: song?.title ?? 'Sin título',
        artist: song?.artist ?? '',
        key: perf.key,
        link: perf.ref_link || song?.ref_link || null, // performance override, else the song's Spotify link
        instruments: instrsByPerf[perf.id] ?? []
      });
    }
    toques = Object.values(byParty).sort((a, b) => a.party.date.localeCompare(b.party.date));
    authState = 'in';
  });
</script>

<div class="flex flex-col">
  <div class="flex flex-row items-center mx-4 m-2">
    <a href="/" class="text-bold text-cold-light flex flex-row gap-2"><ChevronLeft />VOLVER</a>
  </div>
  <h2 class="text-3xl text-white m-4 mb-1">LISTA DE ENSAYO</h2>
  <p class="text-cold-light text-sm mx-4 mb-4">Las canciones que vas a tocar en tus próximos toques.</p>

  {#if authState === 'loading'}
    <div class="text-white p-4 mx-4">Cargando...</div>
  {:else if authState === 'out'}
    <div class="mt-8 mx-4 p-6 bg-base-900 text-white rounded-lg text-center">
      Debes iniciar sesión para ver tu lista de ensayo.
    </div>
  {:else if toques.length === 0}
    <div class="mx-4 p-6 bg-base-900 text-cold-light rounded-lg text-center">
      Aún no tienes canciones por ensayar. Súmate a un setlist para empezar.
    </div>
  {:else}
    {#each toques as t}
      <div class="mb-6">
        <a href={`/parties/${t.party.id}`} class="block mx-4 mb-2">
          <h3 class="text-xl text-yellow">{t.party.title}</h3>
          <span class="text-sm text-cold-light">{dayjs(t.party.date).format('ddd D [de] MMMM, YYYY')}</span>
        </a>
        <ul class="m-4 mt-0 rounded-lg overflow-clip p-0 space-y-[1px]">
          {#each t.songs as s}
            <li class="bg-base-900 px-4 py-3 flex items-start gap-3">
              <div class="flex-1 min-w-0">
                <div class="text-white truncate">{s.title}</div>
                <div class="text-sm text-cold-light truncate">{s.artist}</div>
                <div class="text-xs text-cold-light mt-0.5">
                  {s.instruments.join(', ')}{#if s.key} · Tono: {s.key}{/if}
                </div>
              </div>
              {#if s.link}
                <a href={s.link} target="_blank" rel="noopener" class="text-cold-light hover:text-white shrink-0 inline-flex items-center gap-1 text-sm">
                  Referencia <ExternalLink size={15} />
                </a>
              {/if}
            </li>
          {/each}
        </ul>
      </div>
    {/each}
  {/if}
</div>
