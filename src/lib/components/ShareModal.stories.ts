import type { Meta, StoryObj } from '@storybook/sveltekit';
import ShareModal from './ShareModal.svelte';

const meta: Meta<typeof ShareModal> = {
  title: 'Components/ShareModal',
  component: ShareModal,
  // full-screen so the fixed overlay fills the canvas as it does in the app
  parameters: { layout: 'fullscreen' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof ShareModal>;

export const Default: Story = {
  args: { url: 'https://rockparty.example/parties/10', title: 'Amistad y Amor por el Rock' }
};
