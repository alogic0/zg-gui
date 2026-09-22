import { mount } from './runtime.js';

// Only this synthetic example owns these snapshot hooks and storage policy.
export async function loadWorkspace({ root, url }) {
  const resource = new URL(url, document.baseURI);
  const key = `zg-gui.workspace.session:${new URL('.', resource).pathname}`;
  const response = await fetch(resource);
  if (!response.ok) throw new Error(`WASM fetch failed: ${response.status}`);
  const { instance } = await WebAssembly.instantiate(await response.arrayBuffer());
  const wasm = instance.exports;
  const capacity = wasm.getSessionCapacity();
  let message = 'Saved in this tab · survives page changes and reloads';
  let invalid = false;
  let disposed = false;
  const paint = () => {
    if (!disposed) {
      const status = root.querySelector('[data-save-status]');
      if (status && status.textContent !== message) status.textContent = message;
    }
  };
  try {
    const saved = sessionStorage.getItem(key);
    if (saved !== null) {
      try {
        if (saved.length > Math.ceil(capacity / 3) * 4) throw new Error('Oversized snapshot');
        const binary = atob(saved);
        if (binary.length > capacity) throw new Error('Oversized snapshot');
        const bytes = new Uint8Array(wasm.memory.buffer, wasm.getSessionBuffer(), binary.length);
        for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
        invalid = wasm.restoreSession(bytes.length) !== 1;
      } catch { invalid = true; }
    }
  } catch { /* A denied store is reported by the save attempt below. */ }

  const save = () => {
    try {
      const length = wasm.saveSession();
      if (!length || length > capacity) throw new Error('Snapshot failed');
      const bytes = new Uint8Array(wasm.memory.buffer, wasm.getSessionBuffer(), length);
      let binary = '';
      for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
      sessionStorage.setItem(key, btoa(binary));
      message = invalid ? 'Saved data could not be restored · sample loaded in this tab'
        : 'Saved in this tab · survives page changes and reloads';
    } catch {
      message = 'Saving unavailable · leaving or reloading may lose changes';
    }
    // The host applies the returned patch before updating browser-owned feedback.
    queueMicrotask(paint);
  };
  const mutate = method => (...args) => {
    const length = wasm[method](...args);
    // Hidden task changes can commit without emitting any DOM commands.
    if (method !== 'dispatch' || args[0] !== 8) invalid = false;
    save();
    return length;
  };
  const app = mount({ root, wasm: { ...wasm, dispatch: mutate('dispatch'), setInput: mutate('setInput') } });
  save();
  paint();
  return Object.freeze({ ...app, dispose() { disposed = true; app.dispose(); } });
}
