import type { Meta, StoryObj } from '@storybook/sveltekit';
import SetlistGroupingExplore from './SetlistGroupingExplore.svelte';

// Visual exploration: how to group band-owned songs on a setlist so a band's
// lineup isn't repeated on every row. Each story renders the SAME mock setlist
// (an open jam, a 3-song band run, an open jam breaking it, then a 2-song run)
// at phone width, so the options are directly comparable.
const meta: Meta<typeof SetlistGroupingExplore> = {
  title: 'Explorations/Setlist band grouping',
  component: SetlistGroupingExplore,
  parameters: { layout: 'fullscreen' },
  argTypes: {
    variant: {
      control: 'inline-radio',
      options: ['current', 'a', 'b', 'c'],
      description: 'Which grouping treatment to render'
    }
  }
};

export default meta;
type Story = StoryObj<typeof SetlistGroupingExplore>;

/** Baseline — band name + full member stack repeated on every song. */
export const Current: Story = { args: { variant: 'current' } };

/** A — consecutive songs collapse into one "set" block with a band header. */
export const A_SetBlock: Story = { args: { variant: 'a' } };

/** B — uniform rows; only the first row of a run shows the band + lineup. */
export const B_Continuation: Story = { args: { variant: 'b' } };

/** C — no grouping; the member stack collapses to a compact band chip. */
export const C_CompactChip: Story = { args: { variant: 'c' } };
