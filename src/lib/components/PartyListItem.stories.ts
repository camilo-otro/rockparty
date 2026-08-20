import type { Meta, StoryObj } from '@storybook/sveltekit';
import PartyListItem from './PartyListItem.svelte';

const meta: Meta<typeof PartyListItem> = {
  title: 'Components/PartyListItem',
  component: PartyListItem,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof PartyListItem>;

const base = {
  id: 1,
  title: 'Serenata Rock',
  date: '2026-09-05',
  description: 'Una selección de clásicos de rock en inglés y español.'
};

export const Default: Story = { args: { party: base, venueName: 'Rolling Beers' } };
export const WithoutDescription: Story = {
  args: { party: { ...base, description: null }, venueName: 'Al Rock Burguer' }
};
export const LongTitle: Story = {
  args: { party: { ...base, title: 'Amistad y Amor por el Rock — Mini Festival' }, venueName: 'Morrison Club' }
};
