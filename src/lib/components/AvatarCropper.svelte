<!-- AvatarCropper.svelte — reusable square avatar cropper (#75).
     Picks an image, lets the user pan (drag) + zoom to frame a square, and emits
     a 512x512 WebP Blob (<= ~150 KB). No dependencies; all client-side because
     Supabase image transforms are Pro-only. Reusable for venue/performer avatars.
     Events: crop { blob, previewUrl }, remove. -->
<script lang="ts">
  import { createEventDispatcher, onDestroy } from 'svelte';
  import { Camera, Check, X, Trash2 } from 'lucide-svelte';

  export let initialUrl: string | null = null; // current avatar (edit)
  export let label = 'Foto de la banda';

  const dispatch = createEventDispatcher();
  const FRAME = 240;   // on-screen crop frame (px)
  const OUT = 512;     // exported avatar size (px)
  const MAX_BYTES = 150 * 1024;

  let mode: 'idle' | 'editing' = 'idle';
  let previewUrl: string | null = initialUrl;  // what the idle state shows
  let ownPreview: string | null = null;        // object URL we created (to revoke)
  let fileInput: HTMLInputElement;
  let canvas: HTMLCanvasElement;

  let bitmap: ImageBitmap | null = null;
  let iw = 0, ih = 0;
  let scale = 1, minScale = 1, maxScale = 3;
  let offsetX = 0, offsetY = 0;
  let dragging = false, lastX = 0, lastY = 0;

  function pick() { fileInput?.click(); }

  async function onFile(e: Event) {
    const file = (e.target as HTMLInputElement).files?.[0];
    (e.target as HTMLInputElement).value = ''; // allow re-picking the same file
    if (!file) return;
    try {
      bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' });
    } catch {
      dispatch('error', 'No se pudo leer la imagen.');
      return;
    }
    iw = bitmap.width; ih = bitmap.height;
    minScale = FRAME / Math.min(iw, ih);
    scale = minScale; maxScale = minScale * 3;
    offsetX = (FRAME - iw * scale) / 2;
    offsetY = (FRAME - ih * scale) / 2;
    mode = 'editing';
    // Wait for the canvas to mount, then draw.
    requestAnimationFrame(draw);
  }

  function clampOffsets() {
    const w = iw * scale, h = ih * scale;
    offsetX = Math.min(0, Math.max(FRAME - w, offsetX));
    offsetY = Math.min(0, Math.max(FRAME - h, offsetY));
  }

  function draw() {
    if (!canvas || !bitmap) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, FRAME, FRAME);
    ctx.drawImage(bitmap, offsetX, offsetY, iw * scale, ih * scale);
  }

  function onZoom(e: Event) {
    const next = Number((e.target as HTMLInputElement).value);
    const cx = FRAME / 2, cy = FRAME / 2, ratio = next / scale;
    offsetX = cx - (cx - offsetX) * ratio;
    offsetY = cy - (cy - offsetY) * ratio;
    scale = next;
    clampOffsets(); draw();
  }

  function onPointerDown(e: PointerEvent) {
    dragging = true; lastX = e.clientX; lastY = e.clientY;
    canvas.setPointerCapture(e.pointerId);
  }
  function onPointerMove(e: PointerEvent) {
    if (!dragging) return;
    offsetX += e.clientX - lastX; offsetY += e.clientY - lastY;
    lastX = e.clientX; lastY = e.clientY;
    clampOffsets(); draw();
  }
  function onPointerUp(e: PointerEvent) {
    dragging = false;
    try { canvas.releasePointerCapture(e.pointerId); } catch {}
  }

  async function exportBlob(): Promise<Blob | null> {
    if (!bitmap) return null;
    const out = document.createElement('canvas');
    out.width = OUT; out.height = OUT;
    const octx = out.getContext('2d');
    if (!octx) return null;
    const k = OUT / FRAME;
    octx.drawImage(bitmap, offsetX * k, offsetY * k, iw * scale * k, ih * scale * k);
    for (const q of [0.8, 0.7, 0.6, 0.5]) {
      const blob = await new Promise<Blob | null>((res) => out.toBlob(res, 'image/webp', q));
      if (blob && (blob.size <= MAX_BYTES || q === 0.5)) return blob;
    }
    return null;
  }

  async function apply() {
    const blob = await exportBlob();
    if (!blob) { dispatch('error', 'No se pudo procesar la imagen.'); return; }
    if (ownPreview) URL.revokeObjectURL(ownPreview);
    ownPreview = URL.createObjectURL(blob);
    previewUrl = ownPreview;
    mode = 'idle';
    bitmap?.close?.(); bitmap = null;
    dispatch('crop', { blob, previewUrl });
  }

  function cancel() {
    mode = 'idle';
    bitmap?.close?.(); bitmap = null;
  }

  function remove() {
    if (ownPreview) { URL.revokeObjectURL(ownPreview); ownPreview = null; }
    previewUrl = null;
    dispatch('remove');
  }

  onDestroy(() => { if (ownPreview) URL.revokeObjectURL(ownPreview); bitmap?.close?.(); });
</script>

<div class="flex flex-col gap-2">
  <span class="text-cold-light text-sm">{label} <span class="text-cold-light/60">(opcional)</span></span>

  {#if mode === 'editing'}
    <div class="flex flex-col items-center gap-3 bg-base-900 rounded-lg p-3">
      <!-- svelte-ignore a11y-no-static-element-interactions -->
      <canvas
        bind:this={canvas}
        width={FRAME}
        height={FRAME}
        class="rounded-full touch-none cursor-grab active:cursor-grabbing bg-base-950"
        style="width:{FRAME}px;height:{FRAME}px"
        on:pointerdown={onPointerDown}
        on:pointermove={onPointerMove}
        on:pointerup={onPointerUp}
        on:pointercancel={onPointerUp}
      ></canvas>
      <input type="range" min={minScale} max={maxScale} step="0.01" value={scale} on:input={onZoom} class="w-full max-w-[240px] accent-cold-base" aria-label="Zoom" />
      <div class="flex gap-2">
        <button type="button" on:click={apply} class="bg-cold-base text-white rounded-full px-4 py-1.5 text-sm inline-flex items-center gap-1"><Check size={16} /> Usar</button>
        <button type="button" on:click={cancel} class="border border-cold-light/40 text-cold-light rounded-full px-4 py-1.5 text-sm inline-flex items-center gap-1"><X size={16} /> Cancelar</button>
      </div>
    </div>
  {:else}
    <div class="flex items-center gap-3">
      {#if previewUrl}
        <img src={previewUrl} alt="Avatar de la banda" class="w-16 h-16 rounded-full object-cover border border-cold-base bg-base-900" />
      {:else}
        <div class="w-16 h-16 rounded-full bg-base-900 flex items-center justify-center text-cold-light"><Camera size={22} /></div>
      {/if}
      <div class="flex gap-2">
        <button type="button" on:click={pick} class="border border-cold-light/40 text-cold-light rounded-full px-3 py-1.5 text-sm hover:border-cold-light">{previewUrl ? 'Cambiar' : 'Subir foto'}</button>
        {#if previewUrl}
          <button type="button" on:click={remove} class="text-red-400 hover:text-red-300 text-sm inline-flex items-center gap-1"><Trash2 size={15} /> Quitar</button>
        {/if}
      </div>
    </div>
  {/if}

  <input bind:this={fileInput} type="file" accept="image/*" on:change={onFile} class="hidden" />
</div>
