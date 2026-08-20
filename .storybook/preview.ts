import type { Preview } from '@storybook/sveltekit';
// Load the app's real styles so stories render on the actual dark theme + tokens
// (base-950 background, Roboto Condensed, the color/type scale).
import '../src/app.css';

const preview: Preview = {
  parameters: {
    layout: 'centered'
  }
};

export default preview;
