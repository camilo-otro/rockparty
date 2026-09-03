<script lang="ts">
  import { createEventDispatcher } from 'svelte';
  import { normalizeText } from '$lib/sanitize';
  import { X, Crown, Trash2 } from 'lucide-svelte';

  export let instruments: any[] = [];        // { id, name }
  export let userOptions: any[] = [];         // { id, nickname } — for the member search
  export let currentUserId: string | null = null;
  export let initialName = '';
  export let initialBio = '';
  export let initialWhoCanSignUp = 'members'; // 'members' | 'managers'
  // { user_id, nickname, role: 'manager'|'member', instruments: number[] }
  export let initialMembers: any[] = [];
  export let submitting = false;
  export let submitLabel = 'Crear banda';

  const dispatch = createEventDispatcher();

  let name = initialName;
  let bio = initialBio;
  let whoCanSignUp = initialWhoCanSignUp;
  let members = initialMembers.map((m) => ({ ...m, instruments: [...(m.instruments ?? [])] }));

  // Ensure the creator is always in the roster as a manager. On create they may
  // not be seeded yet (the user store resolves async), so do it reactively off
  // the currentUserId prop; on edit they're already in initialMembers.
  $: if (currentUserId && !members.some((m) => m.user_id === currentUserId)) {
    members = [{ user_id: currentUserId, nickname: 'Tú', role: 'manager', instruments: [] }, ...members];
  }

  let memberInput = '';
  let filtered: any[] = [];

  const instrName = (id: number) => instruments.find((i) => i.id === id)?.name ?? '';

  function handleMemberInput(e: Event) {
    memberInput = (e.target as HTMLInputElement).value;
    const q = memberInput.toLowerCase();
    filtered = q
      ? userOptions.filter((u) => (u.nickname ?? '').toLowerCase().includes(q) && !members.some((m) => m.user_id === u.id)).slice(0, 6)
      : [];
  }
  function addMember(u: any) {
    members = [...members, { user_id: u.id, nickname: u.nickname, role: 'member', instruments: [] }];
    memberInput = '';
    filtered = [];
  }
  function removeMember(user_id: string) {
    members = members.filter((m) => m.user_id !== user_id);
  }
  function toggleRole(m: any) {
    m.role = m.role === 'manager' ? 'member' : 'manager';
    members = members;
  }
  function toggleInstrument(m: any, id: number) {
    m.instruments = m.instruments.includes(id) ? m.instruments.filter((i: number) => i !== id) : [...m.instruments, id];
    members = members;
  }

  function handleSubmit() {
    const cleanName = normalizeText(name, 80);
    if (!cleanName) { dispatch('error', 'La banda necesita un nombre.'); return; }
    const withoutInstruments = members.filter((m) => m.instruments.length === 0);
    if (withoutInstruments.length) {
      dispatch('error', `Falta elegir qué toca ${withoutInstruments[0].nickname}.`);
      return;
    }
    dispatch('submit', {
      name: cleanName,
      bio: normalizeText(bio, 500),
      whoCanSignUp,
      members: members.map((m) => ({ user_id: m.user_id, role: m.role, instruments: m.instruments }))
    });
  }
</script>

<form on:submit|preventDefault={handleSubmit} class="flex flex-col gap-5 p-4">
  <div class="flex flex-col gap-1">
    <label for="band-name" class="text-cold-light text-sm">Nombre de la banda</label>
    <input id="band-name" type="text" bind:value={name} required maxlength="80" class="p-2 border rounded-lg" />
  </div>

  <div class="flex flex-col gap-1">
    <label for="band-bio" class="text-cold-light text-sm">Descripción <span class="text-cold-light/60">(opcional)</span></label>
    <textarea id="band-bio" bind:value={bio} rows="2" maxlength="500" class="p-2 border rounded-lg resize-none"></textarea>
  </div>

  <div class="flex flex-col gap-1">
    <label for="band-signup" class="text-cold-light text-sm">¿Quién puede agendar la banda?</label>
    <select id="band-signup" bind:value={whoCanSignUp} class="p-2 border rounded-lg">
      <option value="members">Cualquier miembro</option>
      <option value="managers">Solo managers</option>
    </select>
  </div>

  <!-- Members + per-member instruments -->
  <div class="flex flex-col gap-2">
    <span class="text-cold-light text-sm">Integrantes</span>

    <div class="relative">
      <input type="text" bind:value={memberInput} on:input={handleMemberInput} placeholder="Buscar músico…" class="p-2 border rounded-lg w-full" />
      {#if filtered.length}
        <ul class="absolute z-10 left-0 right-0 bg-base-950 border rounded-lg shadow mt-1 overflow-hidden">
          {#each filtered as u}
            <li><button type="button" class="w-full text-left p-2 text-white hover:bg-base-900" on:click={() => addMember(u)}>{u.nickname}</button></li>
          {/each}
        </ul>
      {/if}
    </div>

    <div class="flex flex-col gap-3 mt-1">
      {#each members as m (m.user_id)}
        <div class="bg-base-900 rounded-lg p-3 flex flex-col gap-2">
          <div class="flex items-center justify-between gap-2">
            <div class="text-white flex items-center gap-2">
              {m.nickname}{#if m.user_id === currentUserId}<span class="text-cold-light/70 text-xs">(tú)</span>{/if}
            </div>
            <div class="flex items-center gap-1">
              <button type="button" on:click={() => toggleRole(m)}
                class="text-xs uppercase tracking-wide px-2 py-1 rounded-full inline-flex items-center gap-1 transition {m.role === 'manager' ? 'bg-cold-base text-white' : 'border border-cold-light/40 text-cold-light hover:border-cold-light'}">
                <Crown size={12} /> {m.role === 'manager' ? 'Manager' : 'Miembro'}
              </button>
              {#if m.user_id !== currentUserId}
                <button type="button" on:click={() => removeMember(m.user_id)} class="text-red-400 hover:text-red-300 p-1" aria-label="Quitar"><Trash2 size={15} /></button>
              {/if}
            </div>
          </div>
          <div class="flex flex-row flex-wrap gap-2">
            {#each instruments as instrument}
              <button type="button" on:click={() => toggleInstrument(m, instrument.id)}
                aria-pressed={m.instruments.includes(instrument.id)}
                class="px-3 py-1 rounded-full text-sm transition border {m.instruments.includes(instrument.id)
                  ? 'bg-cold-base text-white border-cold-base'
                  : 'bg-base-950 text-cold-light border-base-950 hover:border-cold-light'}">
                {instrument.name}
              </button>
            {/each}
          </div>
        </div>
      {/each}
    </div>
  </div>

  <button class="bg-cold-base text-white rounded-full px-6 py-2 self-start disabled:opacity-60" type="submit" disabled={submitting}>
    {submitting ? 'Guardando…' : submitLabel}
  </button>
</form>
