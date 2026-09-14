import { load } from './runtime.js';

const root = document.querySelector('#app');
try {
  // Exposed only by this example, for the browser acceptance journey.
  window.demo = await load({ root, url: './demo.wasm' });
  root.removeAttribute('aria-busy');
} catch (error) {
  root.textContent = 'The example could not start. Check the browser console.';
  console.error(error);
}
