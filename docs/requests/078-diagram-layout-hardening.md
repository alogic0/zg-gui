# Diagram layout edge cases

Status: specified.

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

- [ ] Neutral workflow fixtures cover long labels, self-links, cycles, parallel
  edges, multi-rank edges and at least 64 nodes.
- [ ] Source-to-SVG and owned-scene replay agree; geometry is finite, nodes do
  not overlap, routes stay in bounds and logical labels are emitted once.
- [ ] Allocation failure and admission limits discard the candidate safely.
- [ ] GUI/browser checks retain named primitives, controls and focus when label
  wrapping, source membership or layout changes.
- [ ] Document limits and repeatable workload measurements separately from
  application adoption and visual acceptance.
