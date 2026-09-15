# Request 015: semantic navigation child slots

Status: provider verified; consumer acceptance is separate.

Allow an empty `nav` to delegate flow-content children to a typed projection.
This preserves semantic navigation and its direct-child layout without adding
an otherwise unnecessary container. Use the existing public slot contract:
consumer-owned children, disjoint IDs, explicit snapshot costs and failure
propagation. Keep single-child-owner validation and rejection of conditional
or loop-contained slots. This request does not change routing or menu policy.

- [x] Validate accepted navigation slots and reject competing text/children,
  value, condition and loop owners without replacing prior compiler output.
- [x] Verify generated navigation and sibling controls survive child leaf changes,
  including short-output failure and retry with the previous snapshot.
- [x] Verify browser node identity, focused navigation and sibling text selection.
- [x] Record native/compiler/browser checks and artifact/memory measurements.

No new runtime command, HTML parser, allocation or mutation path is required.

Verification: `npm test` passed native/compiler checks and 16 Node tests;
`npm run test:browser` passed 13 browser tests. The generated child label emits
only a text command; one-byte output fails and retry uses the previous snapshot.
Browser checks retain the navigation element, focused button, sibling input and
its selection. Compiler rejection leaves the prior generated file intact.

The standalone demo remains 54,949 bytes with 2 initial WASM pages and 3 after
intentional test growth. This extension changes only compiler admission, public
documentation and verification; there is no runtime or host change.
