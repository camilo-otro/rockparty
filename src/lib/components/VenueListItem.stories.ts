import type { Meta, StoryObj } from '@storybook/sveltekit';
import VenueListItem from './VenueListItem.svelte';

const meta: Meta<typeof VenueListItem> = {
  title: 'Components/VenueListItem',
  component: VenueListItem,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof VenueListItem>;

export const Default: Story = {
  args: { venue: { id: 1, name: 'Rolling Beers', area: 'Chapinero' } }
};
export const WithUpcomingCount: Story = {
  args: { venue: { id: 2, name: 'A Fuego', area: 'Chapinero', count: 10 } }
};
export const WithDescription: Story = {
  args: { venue: { id: 3, name: 'Morrison Club', area: 'Usaquén', description: 'Bar de rock en vivo.', count: 2 } }
};
