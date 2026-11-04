// Optional, finite MathML surface. No listeners, observers, timers or core import.
const NS = 'http://www.w3.org/1998/Math/MathML';
const elements = new Set('math mrow mi mn mo mtext mspace mfrac msqrt mroot msub msup msubsup munder mover munderover mstyle mtable mtr mtd'.split(' '));
const widths = new Set('-0.1667em 0.1667em 0.2222em 0.2778em 0.3333em 1em 2em'.split(' '));
const sizes = new Set('0.5em 0.7em 0.8em 0.85em 1em 1.2em 1.44em 1.73em 2.07em 2.49em'.split(' '));
const colors = new Set('black white red green blue cyan magenta yellow gray orange purple brown'.split(' '));

// Deduplicate oversized-payload diagnostics without retaining oversized strings.
// Only rejected inputs use this key; accepted output caching uses exact text.
function oversizedKey(payload) {
  let hash = 2166136261;
  for (let i = 0; i < payload.length; i++) hash = Math.imul(hash ^ payload.charCodeAt(i), 16777619);
  return `over-limit:${payload.length}:${hash >>> 0}`;
}

function validate(tree, limits) {
  if (tree.namespaceURI !== NS || tree.localName !== 'math'
    || tree.attributes.length !== 2 || tree.getAttribute('class') !== 'zig-math'
    || !['inline', 'block'].includes(tree.getAttribute('display'))) throw new Error('Expected one provider MathML root');
  let count = 0;
  const pending = [[tree, 1]];
  while (pending.length) {
    const [node, depth] = pending.pop();
    if (++count > limits.nodes || depth > limits.depth) throw new RangeError('MathML tree exceeds admission limits');
    if (node.nodeType === 3) continue;
    if (node.nodeType !== 1 || node.namespaceURI !== NS || !elements.has(node.localName)
      || (node !== tree && node.localName === 'math')) throw new Error('Unsupported MathML node or namespace');
    if (node !== tree) {
      for (const attribute of node.attributes) {
        const {name, value, namespaceURI} = attribute;
        const tag = node.localName;
        const allowed = namespaceURI === null && (
          (tag === 'mspace' && name === 'width' && widths.has(value))
          || (tag === 'mtd' && name === 'columnalign' && ['right', 'left'].includes(value))
          || (tag === 'mi' && name === 'mathvariant' && value === 'normal')
          || (tag === 'mfrac' && name === 'displaystyle' && ['true', 'false'].includes(value))
          || (tag === 'mfrac' && name === 'linethickness' && value === '0')
          || (tag === 'mover' && name === 'accent' && value === 'true')
          || (tag === 'munder' && name === 'accentunder' && value === 'true')
          || (tag === 'mo' && name === 'stretchy' && value === 'true')
          || (tag === 'mstyle' && name === 'mathsize' && sizes.has(value))
          || (tag === 'mstyle' && name === 'mathcolor' && colors.has(value))
          || (tag === 'mstyle' && name === 'displaystyle' && ['true', 'false'].includes(value))
          || (tag === 'mstyle' && name === 'scriptlevel' && ['0', '1', '2'].includes(value)));
        if (!allowed) throw new Error(`Unsupported MathML attribute: ${name}`);
      }
      if (node.localName === 'mstyle') {
        const style = node.getAttribute('displaystyle'), level = node.getAttribute('scriptlevel');
        const pair = node.attributes.length === 2 && ((style === 'true' && level === '0')
          || (style === 'false' && ['0', '1', '2'].includes(level)));
        const single = node.attributes.length === 1 && (node.hasAttribute('mathsize') || node.hasAttribute('mathcolor'));
        if (!pair && !single) throw new Error('Unsupported MathML style combination');
      }
    }
    for (const child of node.childNodes) pending.push([child, depth + 1]);
  }
}

export function createMathHost({root, onError = error => console.error(error),
  maxBytes = 65536, maxNodes = 4096, maxDepth = 64, maxSurfaces = 64}) {
  for (const limit of [maxBytes, maxNodes, maxDepth, maxSurfaces]) {
    if (!Number.isSafeInteger(limit) || limit < 1) throw new RangeError('Math limits must be positive safe integers');
  }
  const document = root.ownerDocument;
  const encoder = new TextEncoder();
  const records = new Map();
  let disposed = false, updates = 0, rejected = 0;
  function drop(surface) {
    const record = records.get(surface);
    record?.math?.remove();
    records.delete(surface);
  }
  function sync() {
    if (disposed) return;
    const surfaces = [...root.querySelectorAll('[data-math-surface]')]
      .filter(surface => surface.dataset.mathActive !== 'false');
    const current = new Set(surfaces);
    for (const surface of records.keys()) if (!current.has(surface)) drop(surface);
    for (const surface of surfaces) {
      let record = records.get(surface);
      if (!record) {
        if (records.size === maxSurfaces) { rejected++; onError(new RangeError('Too many math surfaces'), {surface}); break; }
        record = {attempt: null, accepted: null, source: null, output: null, math: null};
        records.set(surface, record);
      }
      const sources = [...surface.children].filter(node => node.hasAttribute('data-math-source'));
      const outputs = [...surface.children].filter(node => node.hasAttribute('data-math-output'));
      const source = sources[0], output = outputs[0];
      const payload = source?.textContent ?? '';
      const attempt = payload.length > maxBytes ? oversizedKey(payload) : payload;
      if (record.accepted === payload && record.math?.parentNode === output
        && record.source === source && record.output === output) { record.attempt = attempt; continue; }
      if (record.attempt === attempt && record.source === source && record.output === output
        && (!record.math || record.math.parentNode === output)) continue;
      record.attempt = attempt;
      record.source = source;
      record.output = output;
      try {
        if (sources.length !== 1 || outputs.length !== 1 || !source.hasAttribute('hidden')
          || [...source.childNodes].some(node => node.nodeType !== 3))
          throw new Error('Math surface requires a hidden source and a separate output child');
        if (payload.length > maxBytes || encoder.encode(payload).byteLength > maxBytes)
          throw new RangeError('MathML payload exceeds byte limit');
        const template = document.createElement('template');
        template.innerHTML = payload;
        if (template.content.childNodes.length !== 1 || template.content.firstChild.nodeType !== 1)
          throw new Error('MathML payload must contain exactly one root');
        const math = template.content.firstChild;
        validate(math, {nodes: maxNodes, depth: maxDepth});
        // Validation finishes before any accepted output is removed.
        record.math?.remove();
        output.replaceChildren(math);
        record.math = math;
        record.accepted = payload;
        updates++;
      } catch (error) {
        rejected++;
        onError(error, {surface});
      }
    }
  }
  return Object.freeze({sync, stats: () => ({surfaces: records.size, updates, rejected, disposed}), dispose() {
    if (disposed) return;
    disposed = true;
    for (const surface of records.keys()) drop(surface);
  }});
}
