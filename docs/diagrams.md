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

Instantiate the GUI and layout dependencies for the same target/optimization.
Programmatic consumers may also build the engine's public diagram structures
and capture `layout.draw(.{ .allocator, .sink })` through its owned scene builder.

## Projection and transactions

```zig
const diagrams = @import("zg_diagrams");
const Diagram = diagrams.Diagram(.{ .max_elements = 128, .max_key_bytes = 192 });
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

`Diagram` accepts named `max_elements` and `max_key_bytes` capacities and owns
fixed storage for compact identities.
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

```sh
zig build serve -Ddiagrams=true
```

Open `http://127.0.0.1:4180/diagrams.html`. Each source editor has an explicit
render action, inline error recovery and reset. Invalid input preserves its
accepted drawing. Download SVG exports the accepted scene through the engine
and embeds the current theme's shared paint stylesheet. Both editors support
native keyboard operation; the panels stack on narrow screens. Source edits are
transient; theme preference follows the other examples.

`-Ddiagrams=true` enables the example and diagram checks. Normal builds leave the
lazy layout dependency unused. An isolated core-only package copy was also built
with its optional layout dependency deliberately absent. The public adapter
helper accepts an application-selected module independently of that example
dependency.

Run `zig build test-diagrams -Ddiagrams=true` for native projection, failure/retry,
example and independent-consumer checks. Run `zig build test-all -Ddiagrams=true`
for the complete native/compiler/browser suite. For a focused browser journey,
use `zig build test-browser -Ddiagrams=true -Dbrowser-filter=diagrams`. Browser
steps always execute because their installed assets and browser state can change
independently of the test executable.

Browser verification covers both source editors, named-participant reordering,
retained SVG/shape/label/input identities, focus, insertion/removal, two marker
namespaces, invalid and empty sources, recovery, valid XML export, download
failure, keyboard activation, themes and a 390px viewport. The runs write
measurements, desktop/mobile screenshots and the UI audit under `zig-out`.

Framework evidence is tracked in request 077. These checks establish provider
behavior; consumer visual acceptance and interaction policy remain separate.

## Example limits and measurements

The example admits 32 nodes/participants, 64 links/events and 128 drawing
primitives per scene. Editor markup limits each source to 1024 UTF-16 code units;
the UTF-8 exchange and owned source buffers hold 4096 bytes. Each primitive's
serialized identity fits 128 bytes. A shared fixed allocator reserves 512 KiB
for both scenes and layout scratch; HTML scratch, patch output and SVG export
each reserve 128 KiB. The WASM stack reserves 1 MiB. Exceeding admission or output
capacity preserves the prior accepted drawing and reports an inline error.

Recorded with Zig 0.17.0, safe optimization, stripped wasm32-freestanding, and
the headless Chromium journeys:

| Measurement | Observed value |
| --- | ---: |
| Optional two-editor example WASM | 213,355 bytes |
| Existing basics WASM | 51,715 bytes, unchanged |
| Existing workspace WASM | 173,967 bytes, unchanged |
| Initial linear memory | 2,228,224 bytes (34 pages) |
| Maximum linear memory observed in the measured workload | 2,228,224 bytes |
| Initial HTML for both sample diagrams and editors | 12,539 bytes |
| One-character flow-node label update, after accepting its draft | 195 bytes / 6 commands |

The label workload changes `Read source` to `Read source!` in the default
flowchart. Its projection contains text/geometry commands and no subtree
replacement or append. The browser also checks no linear-memory growth while
editing both diagrams and exporting SVG. These measurements describe this
bounded example and observed workloads; they do not establish process-RAM
measurements, a universal peak-memory guarantee or a consumer budget.

Reproduce the report with `zig build test-browser -Ddiagrams=true
-Dbrowser-filter=diagrams`; inspect `zig-out/diagram-measurements.json`,
`zig-out/diagram-desktop.png` and `zig-out/diagram-mobile.png`.


Layout hardening adds word wrapping, measured sequence rows and note boxes,
self-links and parallel routes. `LayoutOptions` exposes the wrap width and lane
spacing. The engine's larger native workload uses 72 nodes, while this example
retains its smaller UI admission limits. See request 078 for verification.

## Pinned example engine

The `diagram_engine` dependency in `build.zig.zon` pins an immutable GitHub
commit and its Zig package hash. Zig fetches the engine when diagrams are
enabled or explicitly verified. Diagram-enabled installs include its upstream
license under `share/licenses/zig-mermaid-viewer/`.
Core builds can run with the engine absent from the package cache.

```sh
zig build verify-diagram-engine
zig build test-diagrams test-tools -Ddiagrams=true
zig build test-browser -Ddiagrams=true -Dbrowser-filter=diagrams
```

To update the engine, run `zig fetch` with the GitHub URL of the reviewed
commit. Set the URL and printed hash in `build.zig.zon` and keep `.lazy = true`.
Verification rejects unlisted files and symbolic links, then rehashes the
resolved package to catch changes and missing files. Applications can pass
their own compatible engine module to `addDiagrams`.
