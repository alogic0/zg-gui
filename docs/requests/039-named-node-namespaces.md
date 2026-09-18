# Named node namespaces

Provide deterministic compile-time allocation of named numeric node ranges.
Declarations supply a name and count, optionally a fixed first ID for legacy
adoption. Allocate automatic ranges around all fixed reservations regardless of
declaration order. Reject empty/duplicate names, zero IDs/counts, overlap and
32-bit overflow. IDs are rebuild-local, not persistent storage keys.

Expose checked offset/subrange access for repeated template instances. Allocation
must need no runtime allocator or mutable global registry. Consumers own names,
legacy reservations and admission bounds; a reservation alone does not validate
arbitrary arithmetic inside it. Test fixed and automatic interleaving, exhausted
space, boundary IDs, duplicate names, overlaps and child bounds. Provider delivery
and consumer adoption are separate statuses.

Provider delivered: public `namespace.Registry`, `Range` and checked allocation.
Core and generated-template tests pass, including fixed/automatic interleaving,
first-fit holes, bounds, invalid declarations and exhaustion. No runtime storage
or runtime allocation is introduced by compile-time registry use.
