import type { Meta, StoryObj } from '@storybook/sveltekit';
import PerformanceListItem from './PerformanceListItem.svelte';

const meta: Meta<typeof PerformanceListItem> = {
  title: 'Components/PerformanceListItem',
  component: PerformanceListItem,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof PerformanceListItem>;

// All instrument slots open (faded icons = "looking for musicians")
export const AllOpen: Story = {
  args: { title: "Don't Look Back in Anger", artist: 'Oasis', performers: [] }
};

// A couple of slots claimed (avatar rings), the rest still open
export const SomeFilled: Story = {
  args: {
    title: "Don't Look Back in Anger",
    artist: 'Oasis',
    key: 'C',
    performers: [
      { instrument_id: 1, user_id: 'u1', user_avatar: null },
      { instrument_id: 4, user_id: 'u2', user_avatar: null }
    ]
  }
};

// Every instrument filled
export const FullBand: Story = {
  args: {
    title: 'Serenata Rock',
    artist: 'Los hijos de doña Sara',
    performers: [1, 2, 3, 4, 5, 6].map((i) => ({ instrument_id: i, user_id: 'u' + i, user_avatar: null }))
  }
};
