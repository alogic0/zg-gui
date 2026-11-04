# Optional mathematical rendering surfaces

Status: specified; implementation and verification pending.

## Reusable contract

Consumers need optional typesetting through a caller-selected provider without
adding a mandatory parser or math engine to core GUI builds. Register a Zig
adapter through a public build helper, passing the provider's public module.
Use its supported rendering API, not private parser trees.

An owned formula caches its exact source/options and accepted MathML output.
Updates return changed/unchanged or a source diagnostic. Named inputs declare
the allocator and output limit. Allocation/capacity/invalid-source failures
preserve accepted output; callers deinitialize owned storage explicitly.

An opt-in browser math host consumes generated MathML from a declared hidden
source node and owns only a separate output subtree. Validate the detached tree
against a finite namespace, element and fixed attribute/value contract before
installation. Reject URLs, event handlers, arbitrary HTML/styles, unknown
vocabulary and exceeded byte/node/depth limits. Retain accepted output on a
failed update. Unchanged payloads retain their actual MathML DOM objects.

A minimal optional `onPatch(root)` callback runs after a completed DOM projection
(initialize/hydrate/patch), allowing adapters to bind/update declared surfaces.
It must not select application state or business mutations. Existing callback
failure/recovery behavior applies; the math host reports rejected payloads
without throwing through the projection by default.

## Ownership and lifecycle

The application owns source, revisions, state and presentation. The Zig formula
owns copied source/output; returned views borrow until update/deinit. The browser
adapter owns generated MathML descendants and bounded bookkeeping. It drops
removed surfaces on synchronization and releases bookkeeping on dispose. It
installs no timers, observers or listeners. Consumers dispose the adapter with
their GUI. Main content and unrelated focus survive formula changes.

## Acceptance

- [ ] Public registration works in native and freestanding-Wasm consumers.
- [ ] Formula caching, source diagnostics, allocator failure and output limits
      preserve accepted state and have native tests.
- [ ] Browser checks cover real semantic output, malformed payload refusal,
      stable wrappers/unrelated focus, removal, resync and disposal.
- [ ] Core-only consumers build without a provider or math browser module.
- [ ] Public APIs, output vocabulary and failure/lifetime limits are documented.

Provider success does not establish application acceptance. Visual HTML/fonts,
math editing, arbitrary markup injection and complete TeX compatibility are
outside this contract.
