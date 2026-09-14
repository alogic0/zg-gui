# Request 001: reusable template components

Status: requested. Template-level invocation is not implemented.

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

- [ ] Specify invocation syntax, source registration and the typed input API.
- [ ] Specify namespace/ref composition and supported nesting contexts.
- [ ] Implement repeated invocation without extra layout wrappers.
- [ ] Derive combined snapshot capacity and define admission limits.
- [ ] Test independent instance updates, unchanged output and semantic refs.
- [ ] Reject missing/invalid inputs, invalid structure and namespace overflow.
- [ ] Test allocation failure, snapshot exhaustion and recovery.
- [ ] Verify public build integration from an independent consumer package.
- [ ] Verify repeated controls in a neutral browser example, including retained
  DOM objects, focused inputs and globally unique node IDs.
- [ ] Document supported limits and record artifact/memory measurements.

## Open design choices

Invocation syntax, source registration, namespace allocation and component
nesting limits need design and implementation. These are not delivered APIs.
Nested keyed loops, arbitrary external-ID mapping and multiple selection remain
separate roadmap items.

## Verification

Pending. Existing scoped-composition tests do not verify template invocation.
