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

## Planned capabilities

- [ ] Reusable template invocation with typed inputs, stable instance namespaces
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

The next priority is reusable components. Existing scoped templates can be
composed in Zig; template-level invocation is still pending.
Track its contract and acceptance in
[request 001](requests/001-template-components.md). Follow the
[provider workflow](contributing.md) for new capabilities.
