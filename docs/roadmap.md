# Framework roadmap

This roadmap tracks reusable capabilities and framework verification.
Application integration and product acceptance belong to consumers.

## Available capabilities

- [x] Scoped projections, disjoint node ranges and generated semantic references.
- [x] SVG namespaces and dynamic local sprite references.
- [x] Explicit table structure with retained keyed rows.
- [x] Controlled single selects, keyed options and selection recovery.
- [x] Native and browser checks for identity, focus, invalid input and overflow.
- [x] Public build registration verified by an independent consumer package.

- [x] Semantic description lists with retained value leaves; see
  [request 002](requests/002-description-lists.md).

- [x] Typed child-projection slots and checked runtime fragment placement; see
  [request 003](requests/003-projection-composition.md).

- [x] Semantic list slots and explicit list-parent row fragments; see
  [request 004](requests/004-list-fragments.md).

- [x] Table-section slots and explicit row-fragment contexts; see
  [request 005](requests/005-table-fragments.md).

- [x] Single-select child slots; see [request 006](requests/006-select-slots.md).

Semantic time elements are implemented and verified in
[request 007](requests/007-time-elements.md).

## Capability extensions

- [x] Reusable template invocation with typed inputs, stable instance namespaces
  and derived combined snapshot capacity.
- [ ] Nested keyed loops with explicit ownership and admission limits.
- [ ] Stable compact keys for arbitrary external identifiers.
- [ ] Typed multiple selection, change events and recovery.
- [ ] Large-list snapshot measurements and evidence-based improvements.

See [templates](templates.md) and [verification](template-verification.md).
Focus trapping, modal dismissal, routing and business effects remain application
policy. Examples and tests use general-purpose controls and local fixtures.

## Delivery checklist

- [ ] Specify each feature through a neutral capability contract.
- [ ] Implement the public API with explicit ownership and failure behavior.
- [ ] Verify native behavior, consumer build integration and browser interactions.
- [ ] Record limits and artifact/memory measurements separately from correctness.

Reusable components are implemented and verified in
[request 001](requests/001-template-components.md). Further extensions remain
separate requests; invocation within keyed loops is not yet supported. Follow the
[provider workflow](contributing.md) for new capabilities.
