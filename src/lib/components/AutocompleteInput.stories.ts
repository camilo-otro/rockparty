import type { Meta, StoryObj } from '@storybook/sveltekit';
import AutocompleteInput from './AutocompleteInput.svelte';

const meta: Meta<typeof AutocompleteInput> = {
  title: 'Components/AutocompleteInput',
  component: AutocompleteInput,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof AutocompleteInput>;

// Focus the input in the canvas to see the suggestions dropdown.
export const Default: Story = {
  args: {
    id: 'demo',
    placeholder: 'Buscar usuario…',
    value: '',
    suggestions: ['Camilo', 'Sara', 'fuyumehanamura', 'Cami Soto']
  }
};

export const Prefilled: Story = {
  args: {
    id: 'demo2',
    placeholder: 'Buscar…',
    value: 'Cam',
    suggestions: ['Camilo', 'Cami Soto', 'Sara']
  }
};
