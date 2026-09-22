import { load } from './runtime.js';

const root = document.querySelector('#app');
try {
  // Exposed only by this example, for the browser acceptance journey.
  const app = await load({ root, url: './demo.wasm' });
  const disposeTheme = window.demoTheme.bind({ root, app, action: 7 });
  window.demo = Object.freeze({ ...app, dispose() { disposeTheme(); app.dispose(); } });
  root.removeAttribute('aria-busy');
} catch (error) {
  root.textContent = 'The example could not start. Check the browser console.';
  console.error(error);
}
