<script lang="ts">
  // Imports
  import { onMount, onDestroy } from 'svelte';
  import { page } from '$app/state';
  import { supabase } from '$lib/supabaseClient';
  import { ChevronLeft, GripHorizontal, Share2, Edit, MapPin, Plus } from 'lucide-svelte';
  import PerformanceListItem from '../../../lib/components/PerformanceListItem.svelte';
  import { user } from '$lib/stores/user';
  import Sortable from 'sortablejs';
  import ShareModal from '$lib/components/ShareModal.svelte';
  import dayjs from 'dayjs';
  import 'dayjs/locale/es';

  // State variables
  let party: any = null;
  let venue: any = null;
  let performances: any[] =   [];
  let songs: any[] = [];
  let users: any[] = [];
  let partyPerformers: any[] = [];
  let loading = true;
  let error: string | null = null;
  let loadingPerformances = true;
  let errorPerformances: string | null = null;
  let currentUserId: string | null = null;
  let unsubscribeUser: () => void;
  let sortableInstance: Sortable | null = null;
  let sortableList: HTMLElement;
  let showShareModal = false;
  let partyAdmins: string[] = [];
  let usersLoaded = false;

  // Derived helpers
  function getSongTitle(songId: number) {
    const song = songs.find(s => s.id === songId);
    return song ? song.title : 'Sin título';
  }
  function getSongArtist(songId: number) {
    const song = songs.find(s => s.id === songId);
    return song ? song.artist : '';
  }
  function getUserNickname(userId: string) {
    const usr = users.find(u => u.id === userId);
    return usr ? usr.nickname : 'Anónimo';
  }
  function getUserAvatar(userId: string) {
    const usr = users.find(u => u.id === userId);
    return usr && usr.avatarUrl ? usr.avatarUrl : '/images/avatar-default.svg';
  }

  // Sortable functionality
  function initializeSortable() {
    if (sortableList && party?.created_by === currentUserId) {
      sortableInstance = new Sortable(sortableList, {
        animation: 150,
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        handle: '.drag-handle',
        delay: 200,
        delayOnTouchOnly: true,
        onEnd: (evt) => {
          if (evt.oldIndex !== undefined && evt.newIndex !== undefined && evt.oldIndex !== evt.newIndex) {
            const newPerformances = [...performances];
            const draggedItem = newPerformances[evt.oldIndex];
            const draggableList = evt.to.children;
            evt.item.onclick = function(event) {
              event.preventDefault();
            }
            updatePerformanceOrder(performances, draggableList);
          }
        }
      });
    }
  }

  function destroySortable() {
    if (sortableInstance) {
      sortableInstance.destroy();
      sortableInstance = null;
    }
  }

  // Async functions
  async function updatePerformanceOrder(performanceList = performances, draggableList: HTMLCollection | null) {
    if(draggableList && draggableList.length>0){
      for(let i = 0; i<draggableList.length; i++){
        const id = Number(draggableList[i].getAttribute('data-id'));
        const perf = performanceList.find(p => p.id === id);
        if (perf?.order !== i) {
          perf.order = i;
          await supabase
            .from('performance')
            .update({ order: i })
            .eq('id', perf.id);
        }
      }
    }
    else {
      for (let i = 0; i < performanceList.length; i++) {
        if (performanceList[i].order !== i) {
          performanceList[i].order = i;
          await supabase
            .from('performance')
            .update({ order: i })
            .eq('id', performanceList[i].id);
        }
      }
    }
    performances = performanceList;
  }

  function handleShare() {
    const url = window.location.href;
    const title = party?.title || 'te invito a esta Rock Party';
    const text = party?.description || '';
    if (navigator.share) {
      navigator.share({ title, text, url });
    } else {
      showShareModal = true;
    }
  }

  function handleEdit() {
    if (party?.id) {
      window.location.href = `/parties/${party.id}/edit`;
    }
  }

  function closeShareModal() {
    showShareModal = false;
  }

  // Lifecycle
  onMount(async () => {
    unsubscribeUser = user.subscribe(u => {
      currentUserId = u?.id ?? null;
      // Reinitialize sortable when user changes
      destroySortable();
      setTimeout(initializeSortable, 0);
    });
    const id = page.params.id;
    const { data, error: err } = await supabase.from('party').select('*').eq('id', id).single();
    party = data;
    // Fetch party admins
    const { data: adminData } = await supabase.from('party_admin').select('user_id').eq('party_id', id);
    partyAdmins = adminData ? adminData.map(a => a.user_id) : [];
    if (err) {
      error = err.message;
    } else {
      party = data;
      if (party?.venue) {
        const { data: venueData, error: venueErr } = await supabase.from('venue').select('name, address').eq('id', party.venue).single();
        if (!venueErr) {
          venue = venueData;
        }
      }
      // Fetch performances for this party
      const { data: perfData, error: perfErr } = await supabase.from('performance').select('id, song, suggested_by, ref_link, key, order').eq('party', id);
      if (perfErr) {
        errorPerformances = perfErr.message;
      } else {
        let performanceList = perfData ?? [];
        // Check if any performance has a null or undefined order
        const hasNullOrder = performanceList.some(perf => perf.order === null || perf.order === undefined);
        if (hasNullOrder) {
          performanceList.forEach((perf, index) => {
            perf.order = index;
          });
          await updatePerformanceOrder(performanceList, null);
        }
        performances = performanceList.sort((a, b) => (a.order || 0) - (b.order || 0));
        // Fetch all songs and users referenced in performances
        const songIds = [...new Set(performances.map(p => p.song))];
        const userIds = [...new Set(performances.map(p => p.suggested_by))];
        userIds.push(party.created_by);
        const { data: songData } = await supabase.from('song').select('id, title, artist').in('id', songIds);
        
        // Fetch performers and their instruments first
        const { data: perfUsers } = await supabase.from('performance_user').select('user_id, instrument_id, performance_id').in('performance_id', performances.map(p => p.id));
        
        // Add all performer user IDs to the userIds array
        const performerUserIds = [...new Set((perfUsers ?? []).map(p => p.user_id))];
        const allUserIds = [...new Set([...userIds, ...performerUserIds])];
        
        const { data: userData } = await supabase.from('profile').select('id, nickname, avatarUrl: avatar_url').in('id', allUserIds);
        const { data: instrumentData } = await supabase.from('instrument').select('id, name');
        songs = songData ?? [];
        users = userData ?? [];
        usersLoaded = true;
      
        // Group by user and count songs
        const performerMap: Record<string, { user_id: string, instruments: string[], songCount: number }> = {};
        for (const perfUser of perfUsers ?? []) {
          if (!performerMap[perfUser.user_id]) {
            performerMap[perfUser.user_id] = { user_id: perfUser.user_id, instruments: [], songCount: 0 };
          }
          const inst = instrumentData?.find(i => i.id === perfUser.instrument_id);
          if (inst) {
            // Only add instrument if not already present
            if (!performerMap[perfUser.user_id].instruments.includes(inst.name)) {
              performerMap[perfUser.user_id].instruments.push(inst.name);
            }
          }
          performerMap[perfUser.user_id].songCount += 1;
        }
        partyPerformers = Object.values(performerMap).sort((a, b) => b.songCount - a.songCount);

        // Add performers data to each performance
        performances = performances.map(perf => {
          const perfMusicians = (perfUsers ?? []).filter(u => u.performance_id === perf.id);
          
          // Create performers array with user avatars
          const performers = perfMusicians.map(pm => ({
            instrument_id: pm.instrument_id,
            user_id: pm.user_id,
            user_avatar: getUserAvatar(pm.user_id)
          }));
          
          return { ...perf, performers };
        });

        // Initialize sortable after performances are loaded
        setTimeout(initializeSortable, 0);
      }
      loadingPerformances = false;
    }
    loading = false;
  });

  onDestroy(() => {
    destroySortable();
    if (unsubscribeUser) unsubscribeUser();
  });
</script>

<style>
  :global(.sortable-ghost) {
    opacity: 0.4;
  }
  :global(.sortable-chosen) {
    transform: scale(1.02);
  }
  :global(.sortable-drag) {
    transform: rotate(2deg);
  }
  .drag-handle {
    touch-action: none;
  }
</style>

<div class="max-w-xl mx-auto mt-2 p-4 flex flex-col gap-4">
  <div class="flex flex-row w-full justify-between">
    <a href="/parties" class="text-bold text-cold-light flex flex-row"><ChevronLeft />VOLVER</a>
    {#if currentUserId == party?.created_by || partyAdmins && currentUserId && partyAdmins.includes(currentUserId)}
      <button on:click={handleEdit} class="bg-cold-light text-black rounded-lg px-4 py-2 inline-flex items-center gap-2">
        <Edit size={18} />
      </button>
    {/if}
  </div>
  {#if loading}
    <div class="text-white p-4">Cargando...</div>
  {:else if error}
    <div class="text-red-500 p-4">Error: {error}</div>
  {:else if party}
    <div class="flex flex-row justify-between">
      <h2 class="text-4xl text-yellow font-medium">{party.title}</h2>
    </div>
    <div class="">Organizado por: {#if usersLoaded}<img src={getUserAvatar(party.created_by)} alt="User Avatar" class="w-5 h-5 border-yellow rounded-full inline-block mx-2" /><span class="text-cold-light">{getUserNickname(party.created_by)}</span>{/if}</div>
    <div class="text-lg mb-2 text-white">{party.description}</div>
    <div class="mb-2 text-white">{dayjs(party.date).locale('es').format('ddd D [de] MMMM, YYYY')}</div>
    <div class="mb-2 text-cold-light"><MapPin class="inline-block" size={18} /> {venue ? venue.name : 'Cargando...'} - {venue ? venue.address : ''}</div>
    <div class="mt-2 w-full flex items-center">
      <button on:click={handleShare} class="bg-cold-base text-white rounded-lg p-2 px-6 inline-flex items-center gap-2 m-auto">
        Compartir
        <Share2 class="w-5 h-5" />
      </button>
    </div>
    <h3 class="text-3xl text-white font-medium tracking-widest mt-4 mb-2">SETLIST</h3>
    <div class="bg-base-950 rounded-lg overflow-hidden">
      {#if loadingPerformances}
        <div class="text-white">Cargando Setlist...</div>
      {:else if errorPerformances}
        <div class="text-red-500">Error: {errorPerformances}</div>
      {:else if performances.length === 0}
        <div class="text-white">No hay canciones en el Setlist.</div>
      {:else}
        <ul bind:this={sortableList} class="grid grid-cols-1 space-y-[1px]">
          {#each performances as perf, index (perf.id)}
            <li 
              class="bg-base-900 px-4 p-3 transition-all duration-200"
              data-id={perf.id}
            >
              <a href={`/performance/${perf.id}`} class="block">
                <div class="flex items-center gap-2">
                  <span class="text-gray-400 text-3xl font-medium mr-2">{index + 1}</span>
                  <div class="flex-1">
                    <PerformanceListItem
                      title={getSongTitle(perf.song)}
                      artist={getSongArtist(perf.song)}
                      key={perf.key}
                      performers={perf.performers || []}
                    />
                  </div>
                  {#if party?.created_by === currentUserId}
                    <div class="drag-handle cursor-move">
                      <GripHorizontal class="text-cold-light" />
                    </div>
                  {/if}
                </div>
              </a>
            </li>
          {/each}
        </ul>
      {/if}
      <a href={`/performance/create?partyId=${party.id}`} class="w-full bg-cold-base text-white p-3 inline-block text-center">Sugerir una canción <Plus class="inline-block" /></a>
    </div>
    <h3 class="text-3xl text-white font-medium pt-4 mt-2">MÚSICOS</h3>
    <div class="bg-base-950 rounded-lg overflow-hidden mt-2">
      <ul class="space-y-[1px]">
        {#each partyPerformers as performer}
          <li class="flex flex-col bg-base-900 gap-2 p-4">
            <div class="flex flex-row gap-2">
                <img src={getUserAvatar(performer.user_id)} alt="Avatar" class="w-6 h-6 rounded-full" />
                <span class="text-cold-light font-semibold">{getUserNickname(performer.user_id)}</span>
            </div>
            <div class="flex flex-row justify-between">
              <span class="text-sm text-white">{performer.instruments.join(', ')}</span>
              <span class="text-sm text-cold-light font-bold ml-2">{performer.songCount} CANCIÓN{performer.songCount === 1 ? '' : 'ES'}</span>
            </div>
          </li>
        {/each}
        {#if partyPerformers.length === 0}
          <li class="text-cold-light">Nadie se ha anotado aún.</li>
        {/if}
      </ul>
    </div>
    <div class="flex flex-row justify-between mb-4">
      <div class="mt-2 w-full flex items-center">
        <button on:click={handleShare} class="bg-cold-base text-white rounded-lg p-2 px-6 inline-flex items-center gap-2 m-auto">
          Compartir
          <Share2 class="w-5 h-5" />
        </button>
      </div>
    </div>
    {#if showShareModal}
      <ShareModal url={window.location.href} title={party?.title} on:close={closeShareModal} />
    {/if}
    <div class="flex flex-row items-center">
      <a href="/parties" class="text-bold text-cold-light flex flex-row gap-2 mx-4 m-2"><ChevronLeft />VOLVER</a>
    </div>
  {/if}
</div>
