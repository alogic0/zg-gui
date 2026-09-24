import { createDomHost } from './dom.js';
import { declaredInputValue } from './local-datetime.js';

const owners = new WeakMap();
const requiredExports = ['init', 'resync', 'dispatch', 'setInput', 'getRenderBuffer',
  'getRenderLength', 'getRenderMode', 'getExchangeBuffer', 'getExchangeCapacity'];

// A single WASM instance owns one application. Instantiate separately for each root.
export function mount({ root, wasm, onError = error => console.error(error), onStructure }) {
  if (owners.has(root)) throw new Error('Root already has a mounted GUI');
  for (const name of requiredExports) {
    if (typeof wasm[name] !== 'function') throw new Error(`Missing WASM export: ${name}`);
  }
  if (!(wasm.memory instanceof WebAssembly.Memory)) throw new Error('Missing WASM memory');
  const dom = createDomHost({ root, onStructure });
  const window = root.ownerDocument.defaultView;
  const controller = new window.AbortController();
  const encoder = new TextEncoder();
  const decoder = new TextDecoder('utf-8', { fatal: true });
  let disposed = false;
  let initialized = false;
  const assertActive = () => { if (disposed) throw new Error('GUI has been disposed'); };

  function readText(pointer, length) {
    return decoder.decode(new Uint8Array(wasm.memory.buffer, pointer, length));
  }
  function writeExchange(value) {
    assertActive();
    const capacity = wasm.getExchangeCapacity();
    const target = new Uint8Array(wasm.memory.buffer, wasm.getExchangeBuffer(), capacity);
    const { read, written } = encoder.encodeInto(value, target);
    if (read !== value.length) {
      target.fill(0, 0, written);
      throw new RangeError(`WASM exchange payload exceeds ${capacity} bytes`);
    }
    return written;
  }
  function render(length = wasm.getRenderLength()) {
    assertActive();
    const mode = wasm.getRenderMode();
    const projection = readText(wasm.getRenderBuffer(), length);
    if (mode === 0) {
      if (initialized) throw new Error('Full render requires explicit resynchronization');
      dom.initialize(projection);
      initialized = true;
    } else if (mode === 1 && initialized) {
      try { dom.applyPatchStream(projection); }
      catch (error) {
        // Commands may already have applied; snapshots need a complete resync.
        const nextLength = wasm.resync();
        if (wasm.getRenderMode() !== 0) throw new Error('Resync did not return a full projection', { cause: error });
        dom.initialize(readText(wasm.getRenderBuffer(), nextLength));
        onError(error);
      }
    } else throw new Error(`Unknown or premature render mode: ${mode}`);
  }
  function dispatch({ action, value = 0 }) {
    assertActive();
    if (!Number.isInteger(action) || action <= 0 || action > 0xffffffff
      || !Number.isInteger(value) || value < -0x80000000 || value > 0x7fffffff)
      throw new RangeError('Invalid action or signed action value');
    render(wasm.dispatch(action, value));
  }
  function setInput({ kind, value }) {
    assertActive();
    if (!Number.isInteger(kind) || kind <= 0 || kind > 0xffffffff || typeof value !== 'string')
      throw new TypeError('Input requires a positive kind and string value');
    render(wasm.setInput(kind, writeExchange(value)));
  }
  function listen(type, handler) {
    root.addEventListener(type, event => {
      try { handler(event); } catch (error) { onError(error); }
    }, { signal: controller.signal });
  }
  listen('click', event => {
    const control = event.target.closest?.('[data-event]');
    if (!control || !root.contains(control) || control.disabled || control.closest('[inert]')) return;
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    dispatch({ action: Number(control.dataset.event), value: Number(control.dataset.value || 0) });
  });
  for (const type of ['input', 'change']) listen(type, event => {
    const control = event.target.closest?.('[data-input-kind]');
    if (!control || !root.contains(control) || control.disabled || control.closest('[inert]')) return;
    const changeOnly = control.tagName === 'SELECT' || ['checkbox', 'radio'].includes(control.type);
    if ((type === 'change') !== changeOnly) return;
    setInput({ kind: Number(control.dataset.inputKind), value: declaredInputValue(control) });
  });
  const api = Object.freeze({ render, dispatch, setInput, dispose() {
    if (disposed) return;
    disposed = true;
    dom.dispose();
    controller.abort();
    owners.delete(root);
  } });
  owners.set(root, api);
  try { render(wasm.init()); }
  catch (error) { api.dispose(); throw error; }
  return api;
}

export async function load({ root, url, imports = {}, onError, onStructure }) {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`WASM fetch failed: ${response.status}`);
  const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), imports);
  return mount({ root, wasm: instance.exports, onError, onStructure });
}
