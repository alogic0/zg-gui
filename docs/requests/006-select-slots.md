# Request 006: select child slots

Status: implemented and provider-verified. Consumer acceptance is separate.

Allow an empty single `select` to delegate its options to a typed `:slot`.
The callback owns option membership, valid option/optgroup markup, bounds,
child IDs and snapshot costs. Optional `:value` keeps its existing controlled
selection semantics; consumers may instead own selection in their callback.
Text, literal children, conditions, loops and multiple selection remain
incompatible. Failure invalidates the complete candidate output and snapshot.

- [x] Compiler validation and generated callback/value coverage.
- [x] Browser option replacement retains the select, surrounding controls and
  focus, including removal and restoration of the controlled value.
- [x] Existing compiler, package and host regression tests; public docs updated.

This changes compilation only, without runtime protocol or allocation changes.
Provider verification is separate from consumer acceptance.

## Verification

`zig build test-templates`, `npm test` (nine JavaScript checks plus native
checks) and `npm run test:browser` (six browser checks) pass. Generated native
coverage verifies a select slot and controlled value together, escaped option
labels, exact option-only replacement, derived capacity and output failure.
A separate browser host fixture verifies select/sibling identity, focus and
controlled selection when its matching option disappears and returns.

The existing demo remains 54,949 WASM bytes, with two initial memory pages and
three after intentional growth. No runtime or allocation code changed.
Option fragment contexts and slots on optgroup remain outside this request.
