import { load } from './runtime.js';

const root = document.querySelector('#app');
try {
  const navigation = new AbortController();
  let pendingScroll = 0;
  const narrowLayout = matchMedia('(max-width: 980px)');
  const showEditor = () => {
    cancelAnimationFrame(pendingScroll);
    pendingScroll = requestAnimationFrame(() => {
      pendingScroll = 0;
      if (narrowLayout.matches && document.activeElement?.id === 'task-title') {
        root.querySelector('.detail-panel')?.scrollIntoView({ block: 'start', behavior: 'instant' });
      }
    });
  };
  const app = await load({ root, url: './workspace.wasm' });
  const disposeTheme = window.demoTheme.bind({ root, app, action: 8 });
  // The example owns viewport navigation; task data and render focus stay in Zig.
  root.addEventListener('focusin', event => {
    if (event.target.id === 'task-title') showEditor();
  }, { signal: navigation.signal });
  root.addEventListener('click', event => {
    if (!event.target.closest?.('[data-back-to-tasks]')) return;
    cancelAnimationFrame(pendingScroll);
    const target = root.querySelector('[data-selected="true"] .task-title')
      ?? root.querySelector('[aria-label="Find a task"]');
    target?.focus({ preventScroll: true });
    target?.scrollIntoView({ block: 'center', behavior: 'instant' });
  }, { signal: navigation.signal });
  // Example-only handle for reproducible interaction and retention tests.
  window.workspace = Object.freeze({ ...app, dispose() {
    cancelAnimationFrame(pendingScroll);
    navigation.abort();
    disposeTheme();
    app.dispose();
  } });
  root.removeAttribute('aria-busy');
} catch (error) {
  root.textContent = 'The workspace could not start. Reload to try again, or check that WebAssembly is enabled.';
  root.removeAttribute('aria-busy');
  console.error(error);
}
