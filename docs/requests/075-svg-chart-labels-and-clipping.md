# SVG chart labels, descriptions and clipping containers

Status: verified.

## Reusable contract

Compiled SVG charts need text labels and local clipping definitions without
switching to HTML injection or an independent drawing host. Admit SVG `text`,
`tspan`, `desc` and `clipPath`, preserving namespace and case-sensitive names.
Text/tspan accept escaped text bindings and nested tspans. Tspans require a
text/tspan parent. Metadata descriptions accept text only. Clip paths accept
SVG shapes/groups within the existing SVG-only structure contract.

Admit static `clipPathUnits` with its case preserved. Existing typed geometry
and local-reference policies are unchanged; this adds no remote SVG loading,
HTML foreignObject, inline event handlers or arbitrary dynamic styles.
Consumers own scales, layout, accessible descriptions and chart data.

## Acceptance

- [x] Compiler and generated projection checks cover escaped static/dynamic
  labels, nested tspans, descriptions and clipped SVG geometry.
- [x] Invalid namespaces, misplaced tspans and invalid text/metadata children
  fail before a browser repairs their tree.
- [x] Browser checks retain SVG namespace, label/control identity and focus
  through a text update, rendering markup-looking text without interpretation.
- [x] Public documentation and core/template/browser checks pass.

No new protocol command, persistent runtime state or allocator is introduced.
Application visual acceptance and chart-specific performance remain separate.

## Verification

`zig build test -j4` and `zig build test-browser -j4` passed with Zig
0.17.0. The synthetic browser fixture retains the SVG, label, unrelated
control and focus through one escaped text update. Generated-template checks
confirm a text patch without an HTML replacement.

This compiler admission change adds no protocol commands or persistent state.
No chart throughput or application memory claim is made. Browser checks use
local synthetic data; consumer visual and accessibility acceptance is separate.
