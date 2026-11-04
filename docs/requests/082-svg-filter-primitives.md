# SVG filter primitives and local references

Status: specified; implementation and verification pending.

## Reusable contract

SVG projections need bounded local filter definitions for blur, offset,
compositing, color transforms and channel transfer. Admit `filter` under `defs`,
the finite primitive vocabulary `feGaussianBlur`, `feOffset`, `feColorMatrix`,
`feBlend`, `feComposite`, `feMorphology`, `feComponentTransfer`, and `feFuncR/G/B/A`.
Transfer functions require a component-transfer parent; other primitives require
a filter parent. Keep case-sensitive names, namespaces and existing inert SVG
structure rules. Do not admit external filter resources or arbitrary SVG tags.

Static attributes follow a documented finite vocabulary. Dynamic `filter`
references accept only `none`, a local `url(#identifier)`, or null removal.
Dynamic blur deviation uses an explicit finite nonnegative scalar contract.
Consumers own definition IDs, geometry, presentation, namespaces and effects.

## Ownership and failure

Use ordinary caller-owned projection snapshots and output storage. Attribute
changes retain the SVG, definitions, affected shapes and unrelated controls.
Reject bad structure, unknown attributes/modes, invalid numeric values and
non-local references before publishing output. Capacity failure never commits
the candidate snapshot. No filter engine, resource loader or allocation policy
is added to the browser host.

## Acceptance

- [ ] Compiler covers valid structure and rejects misplaced/unknown primitives.
- [ ] Static/dynamic reference and parameter validation have native checks.
- [ ] Browser checks verify namespaces, real filters, identity and sibling focus.
- [ ] Independent consumer uses documented public APIs and isolated definitions.
- [ ] Public documentation and applicable regression checks pass.

Provider verification is separate from consumer visual acceptance. Record patch
work and relevant artifact/memory measurements with their workload and limits.
