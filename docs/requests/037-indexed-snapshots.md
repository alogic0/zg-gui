# Indexed projection snapshots

Provide a public bounded snapshot store keyed by node and property, shared by
the projection engine and custom projection adapters. Lookup must not scan the
entire old snapshot for each property. Keep traversal order for membership walks,
handle hash-bucket collisions by comparing keys, and preserve first-occurrence
semantics for repeated keys. Missing keys are changed; capacity overflow is an
explicit error before insertion. Never retain borrowed input text.

Snapshots own their entries and index and remain freely copyable. Index links
use entry padding; bucket storage is sized for approximately four entries per
bucket. No allocation or external lifetime is introduced. Verify reordering,
conditional disappearance/reappearance, collisions, independent properties,
duplicate keys, overflow and copied snapshot ownership. Consumers measure memory
and patch work separately from provider acceptance.

Provider status: implemented in the public `snapshot` module and adopted by
`Projection`; `zig build test test-templates` passed. Consumer acceptance is
independent and is not claimed by these checks.
