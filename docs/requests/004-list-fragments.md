# Request 004: list slots and contextual row fragments

Status: implemented and verified in the provider, September 14, 2026.

A consumer composing a revision-owned collection needs semantic list markup
without introducing wrappers or a second collection state cache.

- [x] Allow empty `ul` and `ol` projection slots under the existing ownership,
  conditional/loop and capacity restrictions.
- [x] Add explicit `fragment_context = .ul` or `.ol` build options for row
  fragments. The default `.flow` retains existing validation. List contexts
  require direct `li` roots and whitespace-only inter-root text. Nested markup
  keeps normal structural validation; do not emit an artificial list wrapper.
- [x] Expose the option through both build helpers and the compiler CLI as
  `--context=ul` / `--context=ol`, before optional component pairs.
- [x] Verify diagnostics, output preservation, escaped row leaves, exact refs,
  smallest-owner patches and insufficient namespace rejection.
- [x] Document that the caller must mount fragments under the declared parent
  and that slot callbacks must supply valid children. Runtime projection does
  not inspect or repair DOM ancestry.

This extends native template compilation only. Collection membership, admission,
namespace placement, focus policy and callback snapshots remain consumer-owned.
Failed compilation leaves previous output intact. Provider checks are separate
from consumer acceptance; no runtime interpreter or state allocation is added.


## Verification

`npm test` passes native/compiler/generated projection checks and six JavaScript
tests, including CLI context validation and output preservation. Generated list
fixtures verify escaped row labels, a text-only patch that retains the row and
button, and namespace rejection before output. `npm run test:browser` passes
four existing browser regression tests for identity, focus and runtime recovery.
Those browser fixtures do not yet exercise contextual list fragments directly;
consumer acceptance must check the composed list in its DOM host.

The unchanged demo remains 54,949 WASM bytes, with two initial pages and three
after deliberate test growth. No runtime allocator, protocol or memory policy
changed. Context declarations affect native compilation only.
