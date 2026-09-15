# Explicit template identities

Consumers composing compiled and existing render owners need to retain public DOM
identities without assigning every decorative element a legacy ID.

`Namespace.overrides` borrows named local-slot/external-node pairs. Generated
`nodes`, `nodesAt` and projections use the same mapping. The default range remains
reserved. Zero, overflow, duplicate locals or targets, and mappings into another
slot of that range fail with `NamespaceOverflow`; compile-time scopes reject them.
`validateNamespaces` checks cross-range and external-ID collisions. Callers own
lifetime of runtime maps and must validate the complete composition.

Provider verification: `npm test` passed native/generated/compiler checks and all 17
Node tests, including DOM identity/focus regressions.
Consumer adoption is independent. No host or product state policy changes.
