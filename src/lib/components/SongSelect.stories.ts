import type { Meta, StoryObj } from '@storybook/sveltekit';
import SongSelect from './SongSelect.svelte';

const meta: Meta<typeof SongSelect> = {
  title: 'Components/SongSelect',
  component: SongSelect,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof SongSelect>;

const songs = [
  { id: 1, title: 'Bye Bye Bye', artist: '*NSYNC' },
  { id: 2, title: "Don't Look Back in Anger", artist: 'Oasis' },
  { id: 3, title: 'Killing in the Name', artist: 'Rage Against the Machine' }
];

export const Default: Story = {
  args: { songs, value: '', selectedSongId: '', error: '' }
};

export const WithError: Story = {
  args: {
    songs,
    value: 'Canción inexistente',
    selectedSongId: '',
    error: 'La canción aún no ha sido agregada a la app.'
  }
};
