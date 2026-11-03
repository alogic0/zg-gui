# Diagram layout edge cases

Status: implemented and provider verified.

## Reusable contract

Automatic SVG diagrams must remain legible and bounded for long labels, cycles,
self-links, parallel links and larger supported graphs. The layout engine owns
text wrapping, node bounds, routed edge geometry and one label per logical edge.
The optional GUI adapter retains the same typed scene and identity contract.

Preserve original link directions and paint after cycle breaking and dummy-node
insertion. Parallel links use distinct routes and label positions. Self-links
remain visible without preventing rank assignment. Wrapped labels use ordinary
escaped SVG text primitives and fit their node shapes. Expose explicit wrapping
and lane spacing options with validated finite geometry.

## Acceptance

- [x] Neutral workflow fixtures cover long labels, self-links, cycles, parallel
  edges, multi-rank edges and at least 64 nodes.
- [x] Source-to-SVG and owned-scene replay agree; geometry is finite, nodes do
  not overlap, routes stay in bounds and logical labels are emitted once.
- [x] Allocation failure and admission limits discard the candidate safely.
- [x] GUI/browser checks retain named primitives, controls and focus when label
  wrapping, source membership or layout changes.
- [x] Document limits and repeatable workload measurements separately from
  application adoption and visual acceptance.

## Verification

`zig build test-diagrams -Ddiagrams=true -j4` and
`zig build test-browser -Ddiagrams=true -Dbrowser-filter=diagrams -j4` pass.
The shared engine also passes its native allocation-failure and exact SVG replay
checks. A 72-node workflow with cycles, a self-link and a long transition fits a
2 MiB caller allocator. Browser geometry checks keep wrapped lines inside their
retained rectangle, preserving the first label, SVG owner and input focus.

Wrapping is word-based. An unbreakable word expands its shape rather than being
truncated. The optional example still enforces its existing 32-node/128-primitive
admission limits; these are separate from the larger engine workload.
