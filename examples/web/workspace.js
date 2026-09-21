import { load } from './runtime.js';

const root = document.querySelector('#app');
try {
  // Example-only handle for reproducible interaction and retention tests.
  window.workspace = await load({ root, url: './workspace.wasm' });
  root.removeAttribute('aria-busy');
} catch (error) {
  root.textContent = 'The workspace could not start. Reload to try again, or check that WebAssembly is enabled.';
  root.removeAttribute('aria-busy');
  console.error(error);
}
