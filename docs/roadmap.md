# Framework roadmap

This roadmap tracks reusable capabilities and framework verification.
Application integration and product acceptance belong to consumers.

Optional typed diagram projection is specified in
[request 077](requests/077-optional-diagram-rendering.md), with public integration
documented in [diagrams](diagrams.md).

## Available capabilities

- [x] Scoped projections, disjoint node ranges and generated semantic references.
- [x] SVG namespaces and dynamic local sprite references.
- [x] Explicit table structure with retained keyed rows.
- [x] Controlled single selects, keyed options and selection recovery.
- [x] Native and browser checks for identity, focus, invalid input and overflow.
- [x] Public build registration verified by an independent consumer package.
- [x] Bounded post-projection browser requests and optional host events; see
  [request 084](requests/084-browser-requests.md). Consumer policy stays in Zig.
- [x] Shared declarative browser startup and selected asset installation; see
  [request 085](requests/085-shared-browser-startup.md).

- [x] Semantic description lists with retained value leaves; see
  [request 002](requests/002-description-lists.md).

- [x] Typed child-projection slots and checked runtime fragment placement; see
  [request 003](requests/003-projection-composition.md).

- [x] Semantic list slots and explicit list-parent row fragments; see
  [request 004](requests/004-list-fragments.md).

- [x] Table-section slots and explicit row-fragment contexts; see
  [request 005](requests/005-table-fragments.md).

- [x] Single-select child slots; see [request 006](requests/006-select-slots.md).

Semantic time elements are implemented and verified in
[request 007](requests/007-time-elements.md).

Explicit radio choice values are implemented and verified in
[request 008](requests/008-radio-values.md).

## Capability extensions

- [x] Reusable template invocation with typed inputs, stable instance namespaces
  and derived combined snapshot capacity.
- [x] Nested keyed loops with explicit ownership and admission limits.
- [x] Stable compact keys for arbitrary external identifiers.
- [x] Typed multiple selection, change events and recovery.
- [x] Large-list snapshot measurements and evidence-based improvements.
- [x] Component invocation inside keyed loops with derived item namespaces; see
- [x] CSS transition lifecycles and deferred DOM detachment hooks; see
  [request 056](requests/056-css-transitions-and-exit-hooks.md).
- [x] Web Worker offscreen projections and zero-copy binary patch transfers; see
  [request 057](requests/057-web-worker-offscreen-projections.md).

See [templates](templates.md) and [verification](template-verification.md).
Focus trapping, modal dismissal, routing and business effects remain application
policy. Examples and tests use general-purpose controls and local fixtures.

## Delivery checklist

- [ ] Specify each feature through a neutral capability contract.
- [ ] Implement the public API with explicit ownership and failure behavior.
- [ ] Verify native behavior, consumer build integration and browser interactions.
- [ ] Record limits and artifact/memory measurements separately from correctness.

Reusable components are implemented and verified in
[request 001](requests/001-template-components.md). Component invocation
inside keyed loops is implemented and verified under [request 055](requests/055-components-in-keyed-loops.md).
Follow the [provider workflow](contributing.md) for new capabilities.

- [x] [Integer style-variable bindings](requests/010-integer-style-variables.md):
  provider-verified; consumer layout and scroll policy remain separate.

- [x] [Image source bindings](requests/011-image-source-bindings.md): provider-verified;
  URL provenance and external-image permission remain consumer responsibilities.

- [x] [Description-value child slots](requests/012-description-value-slots.md):
  provider verified; consumers own the value content and its snapshot capacity.

- [x] [Semantic navigation slots](requests/015-navigation-slots.md):
  provider verified; consumer menu behavior remains separate.

- Delivered [explicit template identities](requests/016-template-identities.md).
- Delivered [local link bindings](requests/017-local-link-bindings.md).

- Delivered [description-list slots](requests/018-description-list-slots.md).

- [Aside child slots](requests/019-aside-slots.md): provider verified; consumer adoption remains separate.

Typed integer pixel and percentage style values are delivered under
[request 020](requests/020-style-units.md), with fixed-schema admission and
leaf/retry verification.

Dynamic tab order is delivered under [request 021](requests/021-tabindex.md).
Consumers retain keyboard and focus policy.

Delimited integer formatting and typed HTML helpers are delivered under
[request 047](requests/047-delimited-integer-formatting.md).

HTML writer streaming, form element helpers, and zero-allocation data
formatters are delivered under [request 048](requests/048-html-writer-streaming-and-helpers.md).

Cross-engine browser contract verification (Chromium & Firefox Gecko) is
delivered under [request 049](requests/049-multi-engine-browser-contracts.md).

Static HTML template rendering and dual-target SSR code generation are
delivered under [request 050](requests/050-template-html-codegen.md).

Nested keyed loops with explicit ownership and admission limits are
delivered under [request 051](requests/051-nested-keyed-loops.md).

Typed multiple selection, change events, and recovery are
delivered under [request 052](requests/052-multi-selection.md).

Stable compact keys for arbitrary external identifiers (UUIDs, slugs, 64-bit IDs)
are delivered under [request 053](requests/053-compact-keys.md).

Large-list snapshot measurements (500–1000 items) and exact identity tradeoffs
are delivered under [request 054](requests/054-large-list-snapshots.md).

Component invocation inside keyed loops, CSS transitions and exit hooks, and
zero-copy Web Worker offscreen projections are delivered under
[request 055](requests/055-components-in-keyed-loops.md),
[request 056](requests/056-css-transitions-and-exit-hooks.md), and
[request 057](requests/057-web-worker-offscreen-projections.md).

## Delivered milestone: Hydration, Virtualization, and Form Validation
 
- [x] [Hydration and SSR-to-WASM handover](requests/058-hydration-and-ssr-handover.md):
  Adopting pre-rendered static SSR DOM elements on client boot without re-creating nodes or discarding active input focus and draft state.
- [x] [Virtual scrolling and windowed projections](requests/059-virtual-scrolling.md):
  Declarative viewport windowing for 10,000+ item collections with zero heap allocation and overscan slicing.
- [x] [Declarative form validation and dirty tracking](requests/060-form-validation.md):
  Coordinating client-side validation states, dirty/touched flags, and ARIA accessibility feedback with Zig models.

## Delivered milestone: Accessible Modals, ARIA Live Regions, and Global Hotkeys

- [x] [Modal dialogs and focus trapping](requests/061-modal-dialogs-and-focus-trapping.md):
  Declarative dialog focus trapping (:trap-focus, :dialog), Tab/Shift-Tab cycling, background inerting, Escape key dismissal, and focus restoration to the trigger element.
- [x] [ARIA live regions](requests/062-aria-live-regions.md):
  Declarative screen-reader announcement channel (:live="polite|assertive") synchronized with DOM patch streams.
- [x] [Declarative hotkeys and roving tabindex](requests/063-declarative-hotkeys.md):
  Global keyboard shortcuts (:hotkey) and roving tabindex (:roving-tabindex) navigation for accessible toolbars, tablists, and menus.

## Delivered milestone: Web Components, Cross-Frame Binary Sync, and Container Queries

- [x] [Web Component Custom Elements Interop (<zg-view>)](requests/064-web-component-custom-elements.md):
  Autonomous custom element registration `<zg-view>` with optional Shadow DOM encapsulation (`mode: "open" | "closed"`), attribute reflection, and lifecycle detachment cleanups.
- [x] [Cross-Frame Binary Patch Synchronization](requests/065-cross-frame-binary-patch-sync.md):
  Zero-copy binary patch transfers across `postMessage` / `MessagePort` channels with `ArrayBuffer` transfer lists and origin validation.
- [x] [Zero-Allocation Container Queries & Size Observation](requests/066-container-queries-and-size-observation.md):
  Declarative `:observe-size` and `:container` directives coordinating `ResizeObserver` breakpoint reflection (`data-size="compact|standard|expanded"`) without heap allocation.

## Delivered milestone: FLIP Layout Transitions, Island Hydration, and Optimistic UI

- [x] [Zero-Allocation FLIP Layout Transitions (:layout-id)](requests/067-flip-layout-transitions.md):
  Declarative `:layout-id` directive with GPU-accelerated FLIP (First, Last, Invert, Play) transition coordinator for seamless DOM reordering and element moves.
- [x] [Streaming Island Hydration (:hydrate="visible|idle")](requests/068-streaming-island-hydration.md):
  Progressive subtree hydration activated by `IntersectionObserver` viewport entry or `requestIdleCallback` main thread idleness.
- [x] [Declarative Optimistic UI & Rollback Buffers](requests/069-optimistic-ui-and-rollback.md):
  Declarative `:optimistic` attribute directives with client-side rollback snapshot buffers for immediate user confirmation and zero-loss error restoration.
- [x] [Multi-Engine Performance & Binary Patch Benchmark Suite](requests/070-performance-benchmarks.md):
  Automated performance suite verifying 760k+ patch ops/sec throughput, 153µs MessagePort zero-copy transfer latency, and 0 KB memory leak bounds.



