// Node identity belongs to the command protocol, not application state.
export function createNodeRegistry({ root, MutationObserver = root.ownerDocument?.defaultView?.MutationObserver }) {
  const nodes = new Map();
  let identities = new WeakMap();
  let ready = false;
  let pending = [];
  const observer = MutationObserver ? new MutationObserver(records => pending.push(...records)) : null;
  observer?.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-node-id'] });

  function forgetOne(node) {
    const id = identities.get(node);
    if (id === undefined) return;
    const matches = nodes.get(id);
    matches?.delete(node);
    if (matches?.size === 0) nodes.delete(id);
    identities.delete(node);
  }
  function addOne(node) {
    forgetOne(node);
    const id = node.getAttribute('data-node-id');
    if (id === null) return;
    const matches = nodes.get(id) || new Set();
    matches.add(node);
    nodes.set(id, matches);
    identities.set(node, id);
  }
  function visit(subtree, action) {
    if (subtree.nodeType !== 1 && subtree.nodeType !== 11) return;
    if (subtree !== root && subtree.nodeType === 1) action(subtree);
    for (const node of subtree.querySelectorAll('[data-node-id]')) action(node);
  }
  function add(subtree) { visit(subtree, addOne); }
  function forget(subtree) { visit(subtree, forgetOne); }
  function forgetChildren(target) {
    for (const child of target.children) forget(child);
  }
  function rebuild() {
    nodes.clear();
    identities = new WeakMap();
    pending = [];
    observer?.takeRecords();
    add(root);
    ready = true;
  }
  function synchronize() {
    if (!ready) return rebuild();
    const records = pending.concat(observer?.takeRecords() || []);
    pending = [];
    for (const record of records) {
      if (record.type === 'attributes') {
        if (record.target !== root && root.contains(record.target)) addOne(record.target);
        else forgetOne(record.target);
      } else {
        for (const node of record.removedNodes) if (!root.contains(node)) forget(node);
        for (const node of record.addedNodes) if (root.contains(node)) add(node);
      }
    }
  }
  function get(id) {
    if (!/^\d+$/.test(id)) throw new Error(`Invalid Zig patch node id: ${id}`);
    synchronize();
    const matches = nodes.get(id);
    const count = matches?.size || 0;
    if (count !== 1) throw new Error(`Zig patch node ${id} resolved to ${count} elements`);
    const target = matches.values().next().value;
    if (!target.isConnected || !root.contains(target)) {
      forget(target);
      throw new Error(`Zig patch node ${id} is disconnected`);
    }
    return target;
  }
  function dispose() {
    observer?.disconnect();
    pending = [];
    nodes.clear();
    identities = new WeakMap();
    ready = false;
  }
  return Object.freeze({ get, add, forget, forgetChildren, rebuild, dispose });
}
