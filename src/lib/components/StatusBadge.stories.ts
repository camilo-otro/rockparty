import type { Meta, StoryObj } from '@storybook/sveltekit';
import StatusBadge from './StatusBadge.svelte';

const meta: Meta<typeof StatusBadge> = {
  title: 'Components/StatusBadge',
  component: StatusBadge,
  tags: ['autodocs'],
  argTypes: {
    status: {
      control: 'select',
      options: ['draft', 'pending_venue', 'confirmed', 'live', 'completed', 'cancelled'],
      description: 'A party lifecycle status'
    }
  }
};

export default meta;
type Story = StoryObj<typeof meta>;

export const Draft: Story = { args: { status: 'draft' } };
export const PendingVenue: Story = { args: { status: 'pending_venue' } };
export const Confirmed: Story = { args: { status: 'confirmed' } };
export const Live: Story = { args: { status: 'live' } };
export const Completed: Story = { args: { status: 'completed' } };
export const Cancelled: Story = { args: { status: 'cancelled' } };
