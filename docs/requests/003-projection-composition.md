# Request 003: projection composition

Status: implemented and verified in the provider, September 14, 2026.

A consumer may own a revision-based collection renderer and want compiled
markup for its surrounding panel and repeated fragments. Composition must not
force a second state cache or maximum-sized collection snapshot.

- [x] Add an empty `div` or `section` with `:slot="$children"`. The compiler emits
  the stable owner and invokes the typed view value's `project(p, .{ .node = owner })`
  method inside it. The consumer owns projecting children,
  structural reconciliation, admission, descendant namespaces and capacity.
- [x] Reject invalid bindings, content, and conflicting directives.
  Slots are outside loops and conditional subtrees in this version.
- [x] Expose `projectAt(p, view, namespace)` and `nodesAt(namespace)` for runtime
  placement of independently compiled fragments. Keep `Scoped` compatible.
- [x] Validate ranges, generated static slots and arithmetic before projection;
  failure sets the writer flag without publishing candidate output or state.
  Refs use the same checked placement as their projected elements.
- [x] Verify typed composition, retained siblings/focus, dynamic input prefixes,
  insufficient ranges and output/snapshot exhaustion with neutral examples.
- [x] Document explicit capacity ownership and measure the demo.

Slot callbacks use the existing typed projection interface. This adds neither
raw HTML bindings nor a browser interpreter. Consumers must discard failed
candidate output and snapshots and keep sibling fragment namespaces disjoint.

## Verification and limits

`npm test` passes native/compiler tests and five JavaScript tests. Coverage
includes compatible scoped projections, runtime refs, malformed slots,
insufficient and overflowing namespaces before output, snapshot rejection,
existing output-exhaustion recovery, dynamic prefix patches and independent
consumer build registration. `npm run test:browser` passes four tests; the demo
places two panels through a slot and retains that owner, controls, sibling drafts
and focus through selection and list updates.

The demo is 54,949 WASM bytes (previously 54,325), with two initial pages and
three after the deliberate memory-growth test. These measurements do not set
performance targets. The template guide documents callback capacity ownership
and the unsupported loop/conditional slot cases. Consumer adoption is separate.
