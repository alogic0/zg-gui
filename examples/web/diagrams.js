import { mount } from './runtime.js';

const root = document.querySelector('#app');
const decode = new TextDecoder();
const disposeTheme = window.demoTheme.bind({ root: document });
try {
  const response = await fetch('./diagrams.wasm');
  if (!response.ok) throw new Error('Diagram module could not load');
  const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), {});
  const exports = instance.exports;
  const app = mount({ root, wasm: exports });
  const controller = new AbortController();
  let downloadBusy = false;
  async function download(index) {
    if (downloadBusy) return;
    downloadBusy = true;
    const status = root.querySelector('#download-status');
    const button = root.querySelector(`[data-download="${index}"]`);
    const wasFocused = document.activeElement === button;
    const downloadButtons = root.querySelectorAll('[data-download]');
    downloadButtons.forEach(control => { control.disabled = true; control.setAttribute('aria-busy', 'true'); });
    status.textContent = 'Preparing SVG…';
    try {
      if (!exports.exportSvg(index)) throw new Error('SVG export exceeded capacity');
      const svg = decode.decode(new Uint8Array(exports.memory.buffer, exports.getSvgBuffer(), exports.getSvgLength()));
      const response = await fetch('./diagram-paint.css');
      if (!response.ok) throw new Error('SVG style could not load');
      const paint = await response.text();
      const style = getComputedStyle(document.documentElement);
      const variables = ['--ink', '--muted', '--surface', '--accent', '--tint', '--input', '--line']
        .map(name => `${name}:${style.getPropertyValue(name)};`).join('');
      const offset = svg.indexOf('>') + 1;
      const styled = svg.slice(0, offset) + `<style>svg{${variables}}${paint}</style>` + svg.slice(offset);
      const url = URL.createObjectURL(new Blob([styled], { type: 'image/svg+xml' }));
      const link = document.createElement('a');
      link.href = url;
      link.download = index === 0 ? 'flowchart.svg' : 'sequence.svg';
      document.body.append(link);
      link.click();
      link.remove();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      status.textContent = 'SVG downloaded.';
    } catch (error) {
      status.textContent = 'The SVG could not download. Try again.';
      console.error(error);
    } finally {
      downloadBusy = false;
      downloadButtons.forEach(control => { control.disabled = false; control.removeAttribute('aria-busy'); });
      if (wasFocused && document.activeElement === document.body) button.focus({ preventScroll: true });
    }
  }
  root.addEventListener('click', event => {
    const button = event.target.closest?.('[data-download]');
    if (button && root.contains(button)) void download(Number(button.dataset.download));
  }, { signal: controller.signal });
  root.querySelectorAll('form').forEach(form => form.addEventListener('submit', event => event.preventDefault(), { signal: controller.signal }));
  window.diagramExample = Object.freeze({ ...app, wasm: exports, download, dispose() { controller.abort(); disposeTheme(); app.dispose(); } });
  root.removeAttribute('aria-busy');
} catch (error) {
  root.textContent = 'The diagram example could not start. Build with -Ddiagrams=true and reload.';
  root.removeAttribute('aria-busy');
  console.error(error);
}
