# Optional diagram projections

SVG templates work with the core module alone. Automatic layout is opt-in:
applications select a compatible layout module and register the adapter through
the public build helper. The core has no import of the engine or adapter.

```zig
const gui_dep = b.dependency("zg_gui", .{ .target = target, .optimize = optimize });
const layout_dep = b.dependency("layout", .{ .target = target, .optimize = optimize });
app.addImport("zg_diagrams", @import("zg_gui").addDiagrams(b, .{
    .dependency = gui_dep,
    .engine = layout_dep.module("mermaid"),
}));
```

The selected module must expose `Scene`, `drawing.Element` and its typed shape
vocabulary. The adapter's public `engine` export is the same module. It supplies
`buildScene(.{ .allocator, .source, .limits })`, with flowchart and sequence
support, and `scene.renderSvg(allocator)` for standalone export. Every returned
scene owns its strings/geometry and requires `scene.deinit()`; callers free
exported SVG through its allocator.

## Projection and transactions

```zig
const diagrams = @import("zg_diagrams");
const Diagram = diagrams.Diagram(128, 192);
// Reserve Diagram.node_count IDs through the normal namespace registry.
// Add Diagram.snapshot_capacity to the surrounding projection's capacity.
var candidate = accepted_diagram;
try candidate.project(&projection, .{
    .scene = &scene,
    .namespace = diagram_namespace,
    .description = "A labeled process from input to result",
});
// Commit candidate and the next snapshot only after ALL surrounding writers
// and projections succeed. On error discard the candidate output/snapshot.
```

`Diagram(max_elements, max_key_bytes)` owns fixed storage for compact identities.
It performs no heap allocation. The byte capacity includes the entity kind,
index and primitive part as well as the source name. Two banks of compact slots
reserve removed entities until new entities have their own IDs; this prevents
an insertion from adopting a removed entity's DOM object in the same patch.

Nodes, labels and paths retain identity through geometry edits and source
reordering when their logical keys and shape types remain the same. Source-named
nodes and participants have named keys. Edges, events and activation depths use
positional keys. Changing a shape type replaces only that primitive's child;
retained siblings and the SVG owner stay mounted. The scene's group classes are
applied to per-primitive `g` owners to preserve semantic styling.

The namespace must be disjoint from other projections, contain `node_count` IDs,
and stay fixed until the instance is reset/remounted. Marker IDs use its first
node ID as their prefix. A nonempty accessible description supplies both the
SVG's accessible name and its escaped `desc` text.

Admission rejects oversized scenes/keys, duplicate keys, invalid namespaces,
nonfinite/negative geometry, unsupported marker names and polygons above 64
points. Output and snapshot exhaustion leave the instance's identity mapping
unchanged. Output lengths are restored, writer failure flags remain set, and
the caller discards the failed candidate snapshot before retrying. For a render
with multiple diagrams, copy every accepted instance first and commit all copies
together after the entire render succeeds.

Use a bounded allocator for parsing, layout and scene capture, plus explicit
source/node/event/scene limits. Scene limits alone do not bound layout scratch
or arena overhead. Keep the last accepted source/scene when a new source fails.

## Build and verification

`-Ddiagrams=true` enables diagram checks. Normal builds
leave the lazy layout dependency unused. Run `zig build test-diagrams
-Ddiagrams=true` for projection, failure/retry and independent-consumer checks.
Framework evidence is tracked in request 077; application visual acceptance
and interaction policy remain consumer responsibilities.
