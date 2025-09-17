import type { Config } from 'tailwindcss';

export default {
	content: ['./src/**/*.{html,js,svelte,ts}'],

	theme: {
		extend: {
			colors: {
				'cold-base': '#6C04FF',
				'warm-base': '#FF4000',
				'cold-light': '#A395FF',
				'mid': '#71118E',
				'yellow': '#FFAE00',
				'base-950': '#1A1A1A',
				'base-900': '#262626'
			},
			fontFamily: {
				sans: ['Roboto Condensed', 'system-ui', 'sans-serif'],
				serif: ['ui-serif', 'Georgia', 'serif'],
				mono: ['ui-monospace', 'SFMono-Regular', 'Menlo', 'monospace']
			},
			fontWeight: {
				normal: '100',
				medium: '300',
				bold: '400'
			},
			fontSize: {
				sm: '0.875rem',
				base: '1rem',
				lg: '1.125rem',
				xl: '1.25rem',
				'2xl': '1.5rem',
				'3xl': '1.875rem',
				'4xl': '2.25rem',
				'5xl': '3rem'
			}
		}
	},
	plugins: [require('@tailwindcss/typography')]
} as Config;
