import type { Meta, StoryObj } from '@storybook/sveltekit';
import PerformerForm from './PerformerForm.svelte';

const meta: Meta<typeof PerformerForm> = {
  title: 'Components/PerformerForm',
  component: PerformerForm,
  parameters: { layout: 'padded' },
  tags: ['autodocs']
};
export default meta;
type Story = StoryObj<typeof PerformerForm>;

export const Default: Story = {
  args: { initialEmail: 'camilootro@gmail.com', initialNickname: '', submitting: false, success: false, error: '' }
};
export const Submitting: Story = {
  args: { initialEmail: 'camilootro@gmail.com', initialNickname: 'Cami Soto', submitting: true }
};
export const WithError: Story = {
  args: { initialEmail: 'camilootro@gmail.com', initialNickname: '', error: 'All fields are required.' }
};
