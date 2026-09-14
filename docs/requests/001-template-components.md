# Request 001: reusable template components

Status: implemented and verified in the provider, September 14, 2026.

## Reusable problem

Layouts often repeat the same labeled control with different values, actions
and status feedback. A consumer should be able to author that markup once and
invoke it several times with typed data, without duplicating markup or assigning
every descendant node ID manually.

Existing `Scoped` projections allow manual composition in Zig. This request adds
template-level composition while preserving the existing projection and DOM
ownership model.

## Required contract

- Invocation supplies explicit typed view data. The Zig compiler checks missing
  fields, incompatible values and action types; templates do not evaluate
  arbitrary expressions or look up application state implicitly.
- Each invocation has a stable identity and a disjoint descendant namespace.
  Semantic references remain available for consumer-owned focus requests.
- Combined snapshot capacity includes every admitted component instance and
  structural entry. Composition must not hide additional storage requirements.
- Invalid declarations, namespace collisions, unsupported nesting and capacity
  overflow fail explicitly before output is published. There is no partial
  application or silent truncation.
- Local changes update the smallest owning node. An unchanged sibling instance,
  its controls, browser drafts and focus retain their DOM identity.
- Public build registration resolves component sources predictably and rebuilds
  when a component changes. Runtime parsing is not introduced.

## Acceptance checklist

- [x] Specify invocation syntax, source registration and the typed input API.
- [x] Specify namespace/ref composition and supported nesting contexts.
- [x] Implement repeated invocation without extra layout wrappers.
- [x] Derive combined snapshot capacity and define admission limits.
- [x] Test independent instance updates, unchanged output and semantic refs.
- [x] Reject missing/invalid inputs, invalid structure and namespace overflow.
- [x] Test allocation failure, snapshot exhaustion and recovery.
- [x] Verify public build integration from an independent consumer package.
- [x] Verify repeated controls in a neutral browser example, including retained
  DOM objects, focused inputs and globally unique node IDs.
- [x] Document supported limits and record artifact/memory measurements.

## Delivered API and limits

The [template guide](../templates.md#reusable-template-components) specifies
`:component`, explicit `:view`, instance `:ref`, build registration, qualified
references and derived snapshot capacity. Expansion shares the parent template's
slot allocator and adds no layout wrappers or runtime interpreter.

Nested components and component-owned keyed loops are supported. Invocation
inside keyed loops remains explicitly rejected. Nested keyed loops, arbitrary
external-ID mapping and multiple selection remain separate roadmap items.

## Verification

`npm test` passes native/compiler tests and five JavaScript tests, including
allocation failure, invalid source/type diagnostics and independent consumer
registration with component-source rebuild invalidation. `npm run test:browser`
passes four tests including independent instance updates, retained focus/drafts,
keyed rows, SVG namespaces, selection recovery and global node-ID uniqueness.
See [verification evidence](../template-verification.md#reusable-components).
