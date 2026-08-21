<script lang="ts">
	import { toasts, dismissToast, type ToastType } from '$lib/stores/toasts';
	import { fly } from 'svelte/transition';
	import { flip } from 'svelte/animate';
	import { CircleAlert, CircleCheck, Info, X } from 'lucide-svelte';

	const icons = { error: CircleAlert, success: CircleCheck, info: Info } as const;
	const accent: Record<ToastType, string> = {
		error: 'border-l-red-600',
		success: 'border-l-green-500',
		info: 'border-l-cold-base'
	};
	const iconColor: Record<ToastType, string> = {
		error: 'text-red-500',
		success: 'text-green-500',
		info: 'text-cold-light'
	};
</script>

<div class="fixed inset-x-0 bottom-4 z-50 flex flex-col items-center gap-2 px-4 pointer-events-none">
	{#each $toasts as toast (toast.id)}
		<div
			animate:flip={{ duration: 200 }}
			in:fly={{ y: 20, duration: 250 }}
			out:fly={{ y: 20, duration: 200 }}
			class="pointer-events-auto w-full max-w-md bg-base-900 text-white rounded-lg shadow-lg border-l-4 {accent[toast.type]} flex flex-row items-start gap-3 px-4 py-3"
			role={toast.type === 'error' ? 'alert' : 'status'}
		>
			<svelte:component this={icons[toast.type]} size={20} class="{iconColor[toast.type]} shrink-0 mt-0.5" />
			<div class="flex-1 text-sm leading-snug">{toast.message}</div>
			<button
				class="text-cold-light hover:text-white shrink-0"
				on:click={() => dismissToast(toast.id)}
				aria-label="Cerrar"
			>
				<X size={18} />
			</button>
		</div>
	{/each}
</div>
