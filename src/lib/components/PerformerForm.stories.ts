import type { Meta, StoryObj } from '@storybook/sveltekit';
import PerformerForm from './PerformerForm.svelte';

const instruments = [
  { id: 1, name: 'Voz Lider' },
  { id: 2, name: 'Guitarra Lider' },
  { id: 3, name: 'Guitarra Ritmica' },
  { id: 4, name: 'Bajo' },
  { id: 5, name: 'Teclado' },
  { id: 6, name: 'Bateria' }
];

const meta: Meta<typeof PerformerForm> = {
  title: 'Components/PerformerForm',
  component: PerformerForm,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof PerformerForm>;

export const Default: Story = {
  args: { initialEmail: 'camilootro@gmail.com', initialNickname: '', submitting: false, instruments }
};
export const WithInstruments: Story = {
  args: {
    initialEmail: 'camilootro@gmail.com',
    initialNickname: 'Cami Soto',
    instruments,
    initialInstruments: [2, 4]
  }
};
export const Submitting: Story = {
  args: { initialEmail: 'camilootro@gmail.com', initialNickname: 'Cami Soto', submitting: true, instruments }
};
