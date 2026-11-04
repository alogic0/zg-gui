// Finite browser operations selected by Zig. No application state inference.
export function createBrowserHost({root, wasm, onEvent, onError = error => console.error(error)}) {
  if (!(wasm.memory instanceof WebAssembly.Memory)
    || typeof wasm.getHostBuffer !== 'function' || typeof wasm.getHostLength !== 'function'
    || typeof onEvent !== 'function') throw new TypeError('Browser host needs memory, buffer exports and an event receiver');
  const document = root.ownerDocument, window = document.defaultView;
  const decoder = new TextDecoder('utf-8', {fatal:true}), encoder = new TextEncoder();
  const controller = new window.AbortController();
  const frames = new Map(), preferences = new Map(), revisions = new Map();
  let dialogs = new Map(), disposed = false;
  const uint = (n, zero = false) => Number.isInteger(n) && n >= (zero ? 0 : 1) && n <= 0xffffffff;
  const key = k => typeof k === 'string' && /^[A-Za-z0-9_.-]{1,128}$/.test(k);
  function node(id) {
    if (!uint(id)) throw new Error('Browser request requires a positive node ID');
    const matches = root.querySelectorAll(`[data-node-id="${id}"]`);
    if (matches.length !== 1 || !(matches[0] instanceof window.HTMLElement) || !matches[0].isConnected)
      throw new Error('Browser request target is missing or ambiguous');
    return matches[0];
  }
  const fields = {
    dialog:['kind','node','open','cancel','revision'], focus:['kind','owner','node','revision','mode','guard'],
    scroll:['kind','owner','revision','x','y'], scheme:['kind','value','key','revision'],
    frame:['kind','owner','revision','event'], preferences:['kind','owner','event','key'],
  };
  function validate(commands) {
    if (!Array.isArray(commands) || commands.length > 16) throw new Error('Browser batch exceeds request limit');
    const unique = new Set();
    return commands.map(command => {
      if (!command || typeof command !== 'object' || !fields[command.kind]
        || Object.keys(command).length !== fields[command.kind].length
        || Object.keys(command).some(k => !fields[command.kind].includes(k))) throw new Error('Unknown browser request shape');
      const c = {...command};
      if ('owner' in c && !uint(c.owner)) throw new Error('Invalid browser request owner');
      if ('revision' in c && !uint(c.revision, ['scheme','dialog'].includes(c.kind))) throw new Error('Invalid browser request revision');
      const identity = `${c.kind}:${c.owner ?? c.node ?? ''}`;
      if (unique.has(identity)) throw new Error('Duplicate browser request owner');
      unique.add(identity);
      if (c.kind === 'dialog') {
        c.target = node(c.node);
        if (!(c.target instanceof window.HTMLDialogElement) || typeof c.open !== 'boolean' || !uint(c.cancel)
          || (c.open && c.revision === 0)) throw new Error('Invalid native dialog request');
      } else if (c.kind === 'focus') {
        c.target = node(c.node);
        if (!['preserve_scroll','nearest','end'].includes(c.mode) || !['always','if_body'].includes(c.guard)) throw new Error('Invalid focus request');
        if (c.mode === 'end' && !(c.target instanceof window.HTMLTextAreaElement)
          && !(c.target instanceof window.HTMLInputElement && ['text','search','tel','url','password'].includes(c.target.type))) throw new Error('Text-end focus needs a text control');
      } else if (c.kind === 'scroll') {
        if (![c.x,c.y].every(n => Number.isInteger(n) && n >= 0 && n <= 16777216)) throw new Error('Invalid viewport scroll');
      } else if (c.kind === 'scheme') {
        if (!['light','dark'].includes(c.value) || !key(c.key)) throw new Error('Invalid color scheme request');
      } else if (c.kind === 'frame') {
        if (!uint(c.event)) throw new Error('Invalid frame event kind');
      } else if (c.kind === 'preferences') {
        if (!uint(c.event) || !key(c.key)) throw new Error('Invalid preference request');
      }
      return c;
    });
  }
  function emit(kind, value, active) {
    queueMicrotask(() => {
      if (disposed || !active()) return;
      try { onEvent({kind,value:JSON.stringify(value)}); } catch (error) { onError(error); }
    });
  }
  function once(c, action) {
    const k = `${c.kind}:${c.owner ?? c.key}`;
    if (revisions.get(k) === c.revision) return;
    action();
    revisions.set(k,c.revision);
  }
  root.addEventListener('cancel', event => {
    const record = dialogs.get(event.target);
    if (!record?.open) return;
    event.preventDefault();
    emit(record.cancel,{revision:record.revision},() => dialogs.get(event.target) === record);
  },{capture:true,signal:controller.signal});

  function sync() {
    if (disposed) return;
    const length = wasm.getHostLength();
    if (length === 0) return;
    if (!uint(length) || length > 4096) throw new RangeError('Browser batch exceeds byte limit');
    const commands = validate(JSON.parse(decoder.decode(new Uint8Array(wasm.memory.buffer,wasm.getHostBuffer(),length))));
    // Reconcile native modality before any focus or viewport operation.
    const nextDialogs = new Map();
    for (const c of commands.filter(c => c.kind === 'dialog')) {
      const old = dialogs.get(c.target);
      const record = old && old.open === c.open && old.revision === c.revision && old.cancel === c.cancel ? old : c;
      nextDialogs.set(c.target,record);
    }
    for (const [target] of dialogs) if (!nextDialogs.has(target) && target.open) target.close();
    dialogs = nextDialogs;
    for (const [target,c] of dialogs) {
      if (c.open && !target.open) target.showModal();
      if (!c.open && target.open) target.close();
    }
    const revisionKeys = new Set(commands.filter(c => ['focus','scroll','scheme'].includes(c.kind)).map(c => `${c.kind}:${c.owner ?? c.key}`));
    for (const k of revisions.keys()) if (!revisionKeys.has(k)) revisions.delete(k);
    for (const c of commands) {
      if (c.kind === 'scheme') {
        document.documentElement.dataset.theme = c.value;
        if (c.revision) once(c,() => { try { window.localStorage.setItem(c.key,c.value); } catch {} });
      }
      if (c.kind === 'focus') once(c,() => {
        if (c.guard === 'if_body' && document.activeElement !== document.body) return;
        c.target.focus({preventScroll:true});
        if (c.mode === 'nearest') c.target.scrollIntoView({block:'nearest',inline:'nearest',behavior:'instant'});
        if (c.mode === 'end') c.target.setSelectionRange(c.target.value.length,c.target.value.length);
      });
    }
    for (const c of commands.filter(c => c.kind === 'scroll')) once(c,() => window.scrollTo({left:c.x,top:c.y,behavior:'instant'}));
    const wantedFrames = new Set(commands.filter(c => c.kind === 'frame').map(c => c.owner));
    for (const [owner,record] of frames) if (!wantedFrames.has(owner)) {
      if (record.handle !== null) window.cancelAnimationFrame(record.handle);
      frames.delete(owner);
    }
    for (const c of commands.filter(c => c.kind === 'frame')) {
      const old = frames.get(c.owner);
      if (old?.revision === c.revision) continue;
      if (old?.handle != null) window.cancelAnimationFrame(old.handle);
      const record = {...c,handle:null}; frames.set(c.owner,record);
      record.handle = window.requestAnimationFrame(() => {
        record.handle = null;
        if (frames.get(c.owner) !== record) return;
        emit(c.event,{revision:c.revision},() => frames.get(c.owner) === record);
      });
    }
    const wantedPreferences = new Set(commands.filter(c => c.kind === 'preferences').map(c => c.owner));
    for (const owner of preferences.keys()) if (!wantedPreferences.has(owner)) preferences.delete(owner);
    for (const c of commands.filter(c => c.kind === 'preferences')) {
      const old = preferences.get(c.owner);
      if (old?.key === c.key && old.event === c.event) continue;
      const record = {...c}; preferences.set(c.owner,record);
      let stored = null, storage_error = null;
      try {
        stored = window.localStorage.getItem(c.key);
        if (stored !== null && (stored.length > 128 || encoder.encode(stored).byteLength > 128)) { stored = null; storage_error = 'limit'; }
      } catch { storage_error = 'unavailable'; }
      emit(c.event,{system_dark:window.matchMedia('(prefers-color-scheme: dark)').matches,stored,storage_error},() => preferences.get(c.owner) === record);
    }
  }
  function dispose() {
    if (disposed) return;
    disposed = true;
    controller.abort();
    for (const record of frames.values()) if (record.handle !== null) window.cancelAnimationFrame(record.handle);
    frames.clear(); preferences.clear(); revisions.clear();
    for (const [dialog] of dialogs) if (dialog.open) dialog.close();
    dialogs.clear();
  }
  return Object.freeze({sync,dispose,stats:() => ({disposed,frames:[...frames.values()].filter(r => r.handle !== null).length,
    dialogs:dialogs.size,preferences:preferences.size,revisions:revisions.size,listeners:disposed?0:1})});
}
