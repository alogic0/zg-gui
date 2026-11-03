# Optional diagram rendering

Status: implemented and provider verified.

## Reusable contract

Applications need automatically laid out flowcharts and sequence diagrams that
can update through ordinary SVG projections. The framework owns SVG admission,
stable DOM identities, patches and an optional drawing adapter. A caller-selected
layout engine owns parsing, text measurement, geometry and SVG export. Consumers
own source state, interaction policy, descriptions, styling and resource limits.

The core `zg_gui` module must remain independent of a layout engine. Register
the adapter explicitly through a public build helper supplied with the engine
module. Use a typed drawing visitor shared with the engine's SVG export; do not
parse generated SVG or introduce raw-markup template bindings.

## Public API and ownership

- Admit SVG `marker`, case-sensitive marker geometry attributes, and dynamic
  local `marker-start`, `marker-mid` and `marker-end` references. References
  accept only `none` or `url(#identifier)`, with optional removal. Preserve
  namespace, spelling and the existing inert SVG structure contract.
- The optional adapter accepts a bounded scene, a caller-owned node namespace,
  an accessible description and a typed projection. It projects shapes, paths,
  labels and marker definitions through existing HTML and patch writers.
- The engine exposes a drawing visitor and an owned scene with explicit
  `deinit`. Scene strings and geometry outlive parsing and layout scratch data.
  Exported SVG and GUI projections use the same drawing calculations.
- Preserve logical identities for source-named nodes and participants across
  label/geometry changes and source reordering. Document positional identity
  for unnamed events and parallel edges. Shape-type changes may replace that
  shape's smallest owning subtree.
- Namespace marker IDs per mounted diagram. Support two independently updated
  diagrams in the same document without fragment collisions.
- Callers provide allocator/scratch storage and explicit source, scene and
  output limits. Admission failure, invalid input or buffer exhaustion must not
  publish partial output or commit candidate identity/snapshot state. Preserve
  the last accepted scene for retry or caller-selected error presentation.

## Implementation slices

1. Save this neutral contract and its acceptance criteria.
2. Add marker primitives and reference validation to compiler, bindings and DOM
   host; verify initial output, removal, refusal and retained SVG identity.
3. Add the engine's shared drawing visitor and owned bounded scene. Keep the
   existing SVG rendering API compatible and test export equivalence.
4. Add opt-in build registration, bounded scene projection and a general
   flowchart example. Verify independent consumer builds, label/geometry
   patches, insertion/removal and two simultaneous diagrams.
5. Integrate sequence drawing, document supported public APIs, and record
   artifact size, initial/peak memory and representative patch work.

Each working slice receives focused verification and a separate commit.

## Acceptance

- [x] Compiler admits valid markers and rejects invalid SVG nesting.
- [x] Bindings and host reject non-local or malformed dynamic references.
- [x] Shared drawing covers flowcharts and sequence diagrams; standalone SVG
  export retains the engine's existing behavior.
- [x] Public registration works from an independent consumer package.
- [x] Core-only builds do not require or link a diagram engine.
- [x] Two diagrams have distinct marker references and disjoint node IDs.
- [x] Browser checks retain SVG, shapes, labels, unrelated controls and focus
  through label changes, layout updates and insertion/removal.
- [x] Native checks cover empty/invalid sources, allocator failure, scene limits,
  output/snapshot exhaustion, failed-update retry and namespace overflow.
- [x] Example supports accessible descriptions, keyboard-operated controls,
  narrow layouts and SVG export.
- [x] Public documentation and reproducible size/memory/patch measurements
  state workload and limits separately from correctness.

## Limits

The first delivery supports the selected engine's flowchart and sequence
vocabulary. Direct manipulation of nodes/edges, pan/zoom policy and numerical
chart scales remain separate consumer or future capability work. Verification establishes
provider behavior; application visual and accessibility acceptance is separate.

## Verification

SVG primitive slice: `zig build test -j4` and `zig build test-browser -j4`
pass with Zig 0.17.0. Browser coverage includes retained SVG geometry, sibling
focus, optional marker removal and refusal of outside-resource references.

Adapter slice: `zig build test-diagrams -Ddiagrams=true -j4` and
`zig build test -Ddiagrams=true -j4` pass. Checks exercise a generated independent
consumer package through public build registration, named-node reordering,
geometry/text patches, two namespaces, distinct insertion/removal slots, local
shape replacement, failed writer/snapshot retry and invalid admission. Shared
scene capture checks exact SVG replay and all allocation failures in the engine.

Example/browser slice: `zig build test-all -Ddiagrams=true -j4` passes with
Zig 0.17.0. Both source editors retain named drawing primitives and focus through
edits/reordering, invalid/empty sources preserve accepted output, and SVG
download succeeds or reports a recoverable failure. Native keyboard activation,
two themes and desktop/390px geometry pass. Core-only builds also pass when the
lazy layout dependency points to an absent directory. Browser steps always run
against current installed assets instead of reusing a cached executable result.

The strict UI audit and design-context lint pass without warnings. See
[diagram integration and measurements](../diagrams.md) for the public API,
bounded example workload and artifact/memory/patch evidence. Browser screenshots,
measurement JSON and the static audit report are written under `zig-out`.
