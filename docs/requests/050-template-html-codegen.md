# Static HTML template rendering and zero-overhead SSR code generation

Status: implemented and provider verified; consumer acceptance is separate.

Declarative `.gui.html` templates provide compile-time binding validation and
zero-allocation rendering. While client-side WASM uses `Projection` with snapshot
diffing and DOM patch command streams, server-side rendering (SSR), initial page
pre-rendering, and command-line HTTP dashboards require streaming static HTML
without snapshot allocation or patch overhead.

`zg_gui` delivers dual-target template rendering:

- `zg_gui.StaticRenderer`: a lightweight duck-typed projection target that writes
  directly to a caller-owned `zg_gui.html.Writer` without snapshot buffers,
  dynamic array allocations, or patch writers.
- Clean vs. Hydrated markup:
  - Clean HTML (default): omits `data-node-id` attributes for clean, lightweight
    server-rendered HTML.
  - Hydrated HTML: passing `emit_node_ids = true` preserves `data-node-id`
    attributes for seamless client-side WASM hydration.
- Template module exports: every template compiled by `zg-template` now exports:
  - `pub fn renderHtml(writer: anytype, view: anytype) void`: renders clean static
    HTML to `writer`.
  - `pub fn renderHtmlWithNodes(writer: anytype, view: anytype) void`: renders
    static HTML with `data-node-id` hydration anchors.
- Top-level helpers in `zg_gui`:
  - `renderHtml(writer: *Html, template_module: anytype, model: anytype) void`
  - `renderHtmlWithNodes(writer: *Html, template_module: anytype, model: anytype) void`

Verification: unit tests in `tests/templates/generated_test.zig` verify that
compiled templates render clean and hydrated static HTML with matching text
escaping, element structures, and attribute encodings. All template compiler,
generated projection, and repository unit tests pass.
