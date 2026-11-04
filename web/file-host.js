// Bounded UTF-8 file controls. Application policy is supplied through declarations.
export function createFileHost({root,onInput,onError = error => console.error(error)}) {
  const document = root.ownerDocument, window = document.defaultView;
  if (typeof onInput !== 'function') throw new TypeError('File host needs an input receiver');
  const controller = new window.AbortController(), urls = new Map();
  const encoder = new TextEncoder(), decoder = new TextDecoder('utf-8',{fatal:true});
  let reads = new Map(), saves = new Map(), disposed = false;
  const integer = (node,name,max = 0xffffffff) => {
    const raw = node.getAttribute(name);
    if (!/^[1-9][0-9]{0,9}$/.test(raw || '') || Number(raw) > max) throw new Error(`Invalid ${name}`);
    return Number(raw);
  };
  const permitted = node => node.isConnected && root.contains(node) && !node.disabled && !node.closest('[inert]');
  function deliver(kind,value) { try { onInput({kind,value}); } catch(error) { onError(error); } }
  function sync() {
    if (disposed) return;
    const inputs = [...root.querySelectorAll('[data-text-open-kind]')];
    const buttons = [...root.querySelectorAll('[data-text-save]')];
    if (inputs.length + buttons.length > 16) throw new RangeError('Too many file controls');
    const nextReads = new Map(), nextSaves = new Map();
    for (const input of inputs) {
      if (!(input instanceof window.HTMLInputElement) || input.type !== 'file' || input.multiple || input.hasAttribute('data-input-kind')) throw new Error('Expected a single-file input');
      const declaration = {kind:integer(input,'data-text-open-kind'),error:integer(input,'data-text-error-kind'),revision:integer(input,'data-text-revision'),limit:integer(input,'data-text-limit',262144)};
      const old = reads.get(input);
      nextReads.set(input,old && ['kind','error','revision','limit'].every(k => old[k] === declaration[k]) ? old : {...declaration,reader:null});
    }
    for (const button of buttons) {
      if (!(button instanceof window.HTMLButtonElement) || button.hasAttribute('data-event')) throw new Error('Expected a dedicated download button');
      const id = integer(button,'data-text-save');
      const targets = root.querySelectorAll(`[data-node-id="${id}"]`);
      const filename = button.getAttribute('data-text-filename');
      if (targets.length !== 1 || !(targets[0] instanceof window.HTMLTextAreaElement) || !targets[0].isConnected
        || !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(filename || '')) throw new Error('Invalid text download source or basename');
      nextSaves.set(button,{target:targets[0],filename,error:integer(button,'data-text-error-kind'),limit:integer(button,'data-text-limit',262144)});
    }
    for (const [input,record] of reads) if (nextReads.get(input) !== record) record.reader?.abort();
    reads = nextReads; saves = nextSaves;
  }
  root.addEventListener('change',event => {
    const input = event.target, record = reads.get(input);
    if (!record || !permitted(input)) return;
    record.reader?.abort();record.reader = null;
    const files = [...(input.files || [])];input.value = '';
    if (files.length === 0) return;
    if (files.length !== 1) { deliver(record.error,'read_failed');return; }
    const file = files[0];
    if (file.size > record.limit) { deliver(record.error,'too_large');return; }
    const reader = new window.FileReader(); record.reader = reader;
    const active = () => !disposed && permitted(input) && reads.get(input) === record && record.reader === reader;
    reader.onload = () => {
      const accepted = active();
      if (record.reader === reader) record.reader = null;
      if (!accepted) return;
      let value;
      try { value = decoder.decode(reader.result); } catch { deliver(record.error,'invalid_utf8');return; }
      deliver(record.kind,value);
    };
    reader.onerror = () => { const accepted = active();if (record.reader === reader) record.reader = null;if (accepted) deliver(record.error,'read_failed'); };
    reader.onabort = () => { if (record.reader === reader) record.reader = null; };
    try { reader.readAsArrayBuffer(file); } catch { record.reader = null;deliver(record.error,'read_failed'); }
  },{signal:controller.signal});
  root.addEventListener('click',event => {
    const button = event.target.closest?.('[data-text-save]'), record = saves.get(button);
    if (!record || !permitted(button) || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    event.preventDefault();
    if (record.target.value.length > record.limit) { deliver(record.error,'too_large');return; }
    const bytes = encoder.encode(record.target.value);
    if (bytes.length > record.limit) { deliver(record.error,'too_large');return; }
    if (urls.size === 8) { deliver(record.error,'read_failed');return; }
    let url, link;
    try {
      url = window.URL.createObjectURL(new window.Blob([bytes],{type:'text/plain;charset=utf-8'}));
      link = document.createElement('a');link.href = url;link.download = record.filename;
      document.body.append(link);link.click();link.remove();
      const timer = window.setTimeout(() => { window.URL.revokeObjectURL(url);urls.delete(url); },0);
      urls.set(url,timer);
    } catch(error) { if (url) window.URL.revokeObjectURL(url);deliver(record.error,'read_failed');onError(error); }
    finally { link?.remove(); }
  },{signal:controller.signal});
  function dispose() {
    if (disposed) return;disposed = true;
    controller.abort();for (const record of reads.values()) record.reader?.abort();
    reads.clear();saves.clear();
    for (const [url,timer] of urls) { window.clearTimeout(timer);window.URL.revokeObjectURL(url); }
    urls.clear();
  }
  return Object.freeze({sync,dispose,stats:() => ({disposed,controls:reads.size+saves.size,readers:[...reads.values()].filter(r=>r.reader!==null).length,urls:urls.size,listeners:disposed?0:2})});
}
