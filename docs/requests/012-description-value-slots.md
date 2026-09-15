# Request 012: description-value child slots

Status: provider verified; consumer acceptance is separate.

Allow an empty `dd` inside a valid description list to delegate its flow-content
children to a typed projection. Preserve the semantic value element without an
extra wrapper. Existing slot ownership, scoped IDs and caller-owned snapshot
capacity apply. Reject orphan values, nonempty slots, competing child owners,
conditional slots and loop-contained slots before replacing generated output.
Consumers own the child projection and must supply valid flow content.

- [x] Verify generated capacity excludes children and child changes retain the
  description list, term, value and unrelated control.
- [x] Verify short output fails and retry succeeds with the previous snapshot.
- [x] Verify DOM identity and focus through the existing browser host.
- [x] Run compiler, native and package checks; record limits and measurements.

No new runtime parser, protocol command, allocation or DOM mutation path is needed.

Verification: `npm test` passes native/compiler checks and 13 Node tests;
`npm run test:browser` passes 10 tests. The synthetic child update emits only
`T` on its own span; a one-byte output fails and retry retains the old snapshot.
The slot template reserves the standard minimum one entry plus one caller-owned
child entry. The standalone demo stays 54,949 bytes, initially 2 WASM pages and
3 after intentional test growth. No runtime or host change was required.
