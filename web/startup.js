import { mount } from './runtime.js';

const owners = new WeakMap();
const decoder = new TextDecoder('utf-8', {fatal:true});

function assetUrl(value, base, origin) {
  if (typeof value !== 'string' || value.length === 0 || value.length > 2048) throw new TypeError('Expected a bounded asset URL');
  const url = new URL(value, base);
  if (!['http:','https:'].includes(url.protocol) || url.origin !== origin || url.username || url.password || url.hash)
    throw new TypeError('Startup assets must use same-origin HTTP(S) URLs');
  return url.href;
}

async function readManifest(value, document) {
  const url = assetUrl(value,document.baseURI,document.location.origin);
  const response = await fetch(url,{redirect:'error'});
  if (!response.ok) throw new Error(`Application manifest failed: ${response.status}`);
  const bytes = await response.arrayBuffer();
  if (bytes.byteLength > 4096) throw new RangeError('Application manifest exceeds 4096 bytes');
  const manifest = JSON.parse(decoder.decode(bytes));
  const fields = manifest?.version === 2 ? ['version','wasm','browser','math','files'] : ['version','wasm','browser','math'];
  if (!manifest || typeof manifest !== 'object' || Array.isArray(manifest)
    || Object.keys(manifest).length !== fields.length || Object.keys(manifest).some(k => !fields.includes(k))
    || ![1,2].includes(manifest.version) || typeof manifest.browser !== 'boolean' || typeof manifest.math !== 'boolean'
    || (manifest.version === 2 && typeof manifest.files !== 'boolean'))
    throw new TypeError('Invalid application manifest');
  return {url:assetUrl(manifest.wasm,url,document.location.origin),browser:manifest.browser,math:manifest.math,files:manifest.files ?? false};
}

export function getApp(root) { return owners.get(root)?.app; }

// Own one main-thread native instance, its optional adapters, and the GUI owner.
export async function start({root, manifest, url, wasm, imports = {}, browser = false, math = false, files = false,
  onError = error => console.error(error)}) {
  if (owners.has(root)) throw new Error('Root already has a starting or mounted application');
  const document = root?.ownerDocument;
  if (!document?.defaultView || !(root instanceof document.defaultView.HTMLElement) || !root.isConnected)
    throw new TypeError('Application root must be a connected HTML element');
  let complete;
  const owner = {app:undefined,ready:new Promise(resolve => { complete = resolve; })}; owners.set(root,owner);
  const errors = [];
  let errorCount = 0, disposed = false, gui, browserHost, mathHost, fileHost, native = wasm;
  const report = error => {
    errorCount++;
    if (errors.length === 32) errors.shift();
    errors.push(String(error));
    onError(error);
  };
  const release = () => {
    if (disposed) return;
    disposed = true;
    const failures = [];
    for (const cleanup of [() => fileHost?.dispose(), () => browserHost?.dispose(), () => mathHost?.dispose(), () => native?.deinit?.(), () => gui?.dispose()]) {
      try { cleanup(); } catch (error) { failures.push(error); }
    }
    owners.delete(root);
    root.dataset.zgStatus = 'disposed';
    root.removeAttribute('aria-busy');
    for (const error of failures) report(error);
  };
  root.dataset.zgStatus = 'loading'; root.setAttribute('aria-busy','true');
  try {
    if (manifest !== undefined) {
      if (url !== undefined || wasm !== undefined || browser || math || files) throw new TypeError('Manifest and direct startup options are exclusive');
      ({url,browser,math,files} = await readManifest(manifest,root.ownerDocument));
    }
    if (![browser,math,files].every(value => typeof value === 'boolean')) throw new TypeError('Capabilities must be booleans');
    if (!native) {
      const response = await fetch(assetUrl(url,root.ownerDocument.baseURI,root.ownerDocument.location.origin),{redirect:'error'});
      if (!response.ok) throw new Error(`Application WASM failed: ${response.status}`);
      ({instance:{exports:native}} = await WebAssembly.instantiate(await response.arrayBuffer(),imports));
    } else if (url !== undefined) throw new TypeError('Supply native exports or a WASM URL');
    if (!(native?.memory instanceof WebAssembly.Memory)) throw new TypeError('Missing WASM memory');
    if (browser && typeof native.hostEvent !== 'function') throw new Error('Browser capability requires native hostEvent');
    const initialMemoryBytes = native.memory.buffer.byteLength;
    if (math) mathHost = (await import('./math-host.js')).createMathHost({root,onError:report});
    if (browser) browserHost = (await import('./browser-host.js')).createBrowserHost({root,wasm:native,onError:report,
      onEvent:event => gui.hostEvent(event)});
    if (files) fileHost = (await import('./file-host.js')).createFileHost({root,onError:report,onInput:event => gui.setInput(event)});
    gui = mount({root,wasm:native,onError:report,onPatch:() => { mathHost?.sync(); browserHost?.sync(); fileHost?.sync(); }});
    const features = Object.freeze({browser,math,files});
    const app = Object.freeze({...gui,wasm:native,features,initialMemoryBytes,diagnostics:() => errors.slice(),
      resources:() => ({disposed,errors:errorCount,browser:browserHost?.stats() ?? null,files:fileHost?.stats() ?? null,
        math:mathHost?.stats() ?? {surfaces:0,updates:0,rejected:0,disposed}}),dispose:release});
    owner.app = app;
    complete(app);
    root.dataset.zgStatus = 'ready'; root.removeAttribute('aria-busy');
    root.dispatchEvent(new root.ownerDocument.defaultView.CustomEvent('zg:ready',{detail:app}));
    return app;
  } catch (error) {
    release();
    complete(undefined);
    root.dataset.zgStatus = 'error';
    if (root.hasAttribute('data-zg-error')) root.textContent = root.getAttribute('data-zg-error');
    report(error);
    throw error;
  }
}

export async function startDeclaredApps({document = globalThis.document, onError} = {}) {
  return Promise.all([...document.querySelectorAll('[data-zg-app]')].map(root => {
    if (owners.has(root)) return owners.get(root).ready;
    return start({root,manifest:root.getAttribute('data-zg-app'),onError}).catch(() => undefined);
  }));
}
