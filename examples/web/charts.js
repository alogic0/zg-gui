import { mount } from './runtime.js';

const root = document.querySelector('#app');
const disposeTheme = window.demoTheme.bind({ root: document });
try {
  const response = await fetch('./charts.wasm');
  if (!response.ok) throw new Error('Chart module could not load');
  const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), {});
  const app = mount({ root, wasm: instance.exports });
  let width = 0;
  const observer = new ResizeObserver(entries => {
    const next = Math.max(320, Math.min(720, Math.floor(entries[0].contentRect.width)));
    if (next === width) return;
    width = next;
    app.setInput({ kind: 2, value: String(width) });
  });
  observer.observe(root.querySelector('.chart-canvas'));
  const controller = new AbortController();
  root.querySelector('form').addEventListener('submit', event => event.preventDefault(), { signal: controller.signal });
  window.chartExample = Object.freeze({ ...app, wasm: instance.exports, dispose() { observer.disconnect(); controller.abort(); disposeTheme(); app.dispose(); } });
  root.removeAttribute('aria-busy');
} catch (error) {
  root.textContent = 'The chart example could not start. Build the examples and reload.';
  root.removeAttribute('aria-busy');
  console.error(error);
}
