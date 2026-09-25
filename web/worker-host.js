import { createDomHost } from './dom.js';
import { declaredInputValue } from './local-datetime.js';

const owners = new WeakMap();

export function mountWorker({
  root,
  worker,
  workerUrl,
  wasmUrl,
  wasmBytes,
  wasmModule,
  imports = {},
  hydrate = false,
  onError = error => console.error(error),
  onStructure,
}) {
  if (owners.has(root)) throw new Error('Root already has a mounted GUI');

  const document = root.ownerDocument;
  const window = document.defaultView;
  const dom = createDomHost({ root, onStructure });
  const controller = new window.AbortController();

  let actualWorker = worker;
  let ownsWorker = false;
  if (!actualWorker) {
    const url = workerUrl || new URL('./projection-worker.js', import.meta.url);
    actualWorker = new window.Worker(url, { type: 'module' });
    ownsWorker = true;
  }

  let disposed = false;
  let initialized = false;
  let readyResolve, readyReject;
  const readyPromise = new Promise((resolve, reject) => {
    readyResolve = resolve;
    readyReject = reject;
  });

  const onMessage = (event) => {
    if (disposed) return;
    const msg = event.data;
    if (!msg || typeof msg !== 'object') return;
    try {
      if (msg.type === 'render') {
        const { mode, length, buffer } = msg;
        const bytes = new Uint8Array(buffer, 0, length);
        if (mode === 0) {
          if (hydrate) {
            try {
              dom.hydrate(bytes);
            } catch (err) {
              onError(err);
            }
          } else {
            dom.initialize(bytes);
          }
          initialized = true;
          readyResolve();
        } else if (mode === 1 && initialized) {
          try {
            dom.applyPatchStream(bytes);
          } catch (patchError) {
            actualWorker.postMessage({ type: 'resync' });
            onError(patchError);
          }
        } else {
          onError(new Error(`Unknown or premature render mode from worker: ${mode}`));
        }
        // Zero-copy transfer to return the buffer to the worker pool
        actualWorker.postMessage({ type: 'recycle', buffer }, [buffer]);
      } else if (msg.type === 'ready') {
        readyResolve();
      } else if (msg.type === 'error') {
        const err = new Error(msg.message);
        if (msg.stack) err.stack = msg.stack;
        onError(err);
        readyReject(err);
      }
    } catch (err) {
      onError(err);
    }
  };

  const onWorkerError = (event) => {
    const err = event.error || new Error(event.message || 'Worker encountered an unhandled error');
    onError(err);
    readyReject(err);
  };

  if (typeof actualWorker.addEventListener === 'function') {
    actualWorker.addEventListener('message', onMessage);
    actualWorker.addEventListener('error', onWorkerError);
  } else {
    actualWorker.onmessage = onMessage;
    actualWorker.onerror = onWorkerError;
  }

  // Kick off initialization in worker
  actualWorker.postMessage({ type: 'init', wasmUrl, wasmBytes, wasmModule, imports });

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

  function dispatch({ action, value = 0 }) {
    if (disposed) throw new Error('GUI has been disposed');
    if (!Number.isInteger(action) || action <= 0 || action > 0xffffffff
      || !Number.isInteger(value) || value < -0x80000000 || value > 0x7fffffff) {
      throw new RangeError('Invalid action or signed action value');
    }
    actualWorker.postMessage({ type: 'dispatch', action, value });
  }

  function setInput({ kind, value }) {
    if (disposed) throw new Error('GUI has been disposed');
    if (!Number.isInteger(kind) || kind <= 0 || kind > 0xffffffff || typeof value !== 'string') {
      throw new TypeError('Input requires a positive kind and string value');
    }
    actualWorker.postMessage({ type: 'setInput', kind, value });
  }

  function dispose() {
    if (disposed) return;
    disposed = true;
    try { actualWorker.postMessage({ type: 'dispose' }); } catch (_) {}
    if (ownsWorker) {
      if (typeof actualWorker.terminate === 'function') actualWorker.terminate();
    }
    dom.dispose();
    controller.abort();
    owners.delete(root);
  }

  const api = Object.freeze({
    dispatch,
    setInput,
    dispose,
    ready: readyPromise,
    worker: actualWorker,
    dom,
  });

  owners.set(root, api);
  return api;
}

export { mountWorker as createWorkerDomHost };
