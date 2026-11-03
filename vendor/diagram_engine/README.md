# Zig Mermaid Viewer

A native, local-first Mermaid diagram viewer and typesetter in pure Zig.

## Component Sub-Libraries

The modular libraries specified in [`PLAN.md`](PLAN.md) are fully implemented within this repository and exported as independent submodules in `build.zig` for modular consumption:

| Planned Library | Implementation File(s) | Exported Module | Description |
| :--- | :--- | :--- | :--- |
| **`zig-graph`** | [`src/graph.zig`](src/graph.zig) | `graph` | Directed graphs, adjacency lists, topological sort, greedy Feedback Arc Set (FAS) cycle breaking |
| **`zig-font-metrics`** | [`src/font_metrics.zig`](src/font_metrics.zig), [`src/font_metrics_data.zig`](src/font_metrics_data.zig) | `font_metrics` | Headless text width measurement and multi-line wrapping with TrueType build generator ([`tools/gen_diagram_font_metrics.zig`](tools/gen_diagram_font_metrics.zig)) |
| **`zig-svg`** | [`src/svg.zig`](src/svg.zig) | `svg` | Deterministic, type-safe SVG element and attribute generator with semantic CSS classes |
| **`zig-mermaid-parser`** | [`src/flowchart_parser.zig`](src/flowchart_parser.zig), [`src/sequence_parser.zig`](src/sequence_parser.zig) | `flowchart_parser`, `sequence_parser` | Zero-dependency AST and parsers for Flowcharts and Sequence diagrams |
| **`zig-graph-layout`** | [`src/sequence_layout.zig`](src/sequence_layout.zig), [`src/sugiyama_layout.zig`](src/sugiyama_layout.zig) | `sequence_layout`, `sugiyama_layout` | 1D linear timeline solver and 5-stage Sugiyama layered layout engine (layering, crossing, coordinate assignment) |
| **`zig-mermaid`** | [`src/root.zig`](src/root.zig) | `mermaid`, `mermaid_viewer` | Unified facade offering high-level `renderDiagramToSvg(allocator, source)` |

## Architecture & Implementation Plan

See [`PLAN.md`](PLAN.md) for the comprehensive architectural specification, layout algorithms, SVG security constraints, and design decisions.

## Owned drawing scenes

```zig
var scene = try mermaid.buildScene(.{
    .allocator = allocator,
    .source = "graph LR\n A[Read] --> B[Process]",
    .limits = .{ .max_nodes = 64, .drawing = .{ .max_elements = 512 } },
});
defer scene.deinit();
const svg_bytes = try scene.renderSvg(allocator);
defer allocator.free(svg_bytes);
```

Scenes copy labels, paths, points and semantic entity keys. They remain usable
after the source buffer and layout are released. `elements.items` exposes typed
rectangles, circles, polygons, lines, paths and labels; `commands.items` retains
paint order and group boundaries for export. For another drawing backend, use
`FlowchartLayout.draw(.{ .allocator = allocator, .sink = &sink })` or the same
method on `SequenceLayout`. Sinks copy borrowed values before returning; the
existing `SvgWriter` and public `drawing.Builder` provide reference implementations.

Use a fixed/budgeted allocator to cap total parsing, layout and scene memory.
`SceneLimits` also limits source bytes, nodes, links/events, captured elements and
copied data. On error no scene is returned and candidate allocations are released.
Named node/participant identities survive label edits and source reordering;
unnamed edge/event identities are positional. GUI hosts own stable compact key
mapping, marker namespaces, DOM admission, descriptions and interactive policy.


## Layout bounds and wrapping

Flowchart and sequence `LayoutOptions.max_label_width` defaults to 200 pixels.
Labels wrap at word boundaries and explicit line breaks. A word wider than the
limit remains intact, with its shape expanding to fit. Flow node heights,
sequence headers, note boxes and timeline rows use measured text heights.
Self-links route outside their node; parallel and opposite flow links receive
separate lanes with preserved directions/paint. Long logical edges emit one
label even when the solver inserts multiple dummy segments.

Use the public layout solvers to select wrapping/lane spacing, then draw into
`drawing.Builder` for an owned scene. Options reject nonfinite/invalid sizes.
Source admission and caller allocator budgets remain separate from layout
quality. The regression workload includes long prose, cycles, self-links,
parallel links, multi-rank transitions and a 72-node graph inside a 2 MiB fixed
allocation budget; it is not a universal memory or throughput guarantee.
