# Initial template compiler and demo verification

September 14, 2026; compiler pinned by `.zigversion`.

The HTML tokenizer, character-reference data, syntax types and directive utilities
come from the pinned local SuperHTML copy. No original package files were edited.
Vendored hashes and the MIT license live in `vendor/superhtml/`.

The native compiler produces normal Zig projection code; no parser, AST or
source-template buffer is linked into the browser runtime. The demo no longer
contains a handwritten `project` function or embedded HTML strings. Its template
and Zig view are built together for native checks and WASM.

Validation performed:

- `zig build test-tokenizers`: seven tests from three independent module roots.
- `zig build test-templates`: compiler validation/allocation-failure checks and
  generated projection tests for exact text patches, property updates,
  conditional child owners, keyed membership/reordering, overflow and recovery.
- `npm test`: the native suite, build, DOM/date checks, vendored hash check,
  expected template/type diagnostics and external package integration.
- `npm run test:browser`: the generated demo's retained controls, focus and
  selection, typed input/events, theme, visibility, Unicode admission,
  keyed-list identity and ID uniqueness, disposal/remount, memory growth and
  missing-target resynchronization. Normal interaction reports no console/page
  errors. A separate DOM protocol test verifies malformed-command rejection.
- Desktop and mobile screenshots inspected; no mobile horizontal overflow.
- `git diff --check` and Zig formatting checks.

Measured demo after conversion: 34,275-byte ReleaseSafe WASM, two initial 64 KiB
memory pages including its 64 KiB stack. Initial HTML is 2,579 bytes; the full
128-byte draft with worst-case quote escaping and all three rows needs 4,350
bytes. Scratch/output capacities are 8 KiB each to admit that supported state.
The old handwritten demo was 25,255 bytes; the generated example adds typed
adapters, more identified leaves and generic keyed-row validation. This is a
functional extraction, not a performance improvement claim. Peak stack/heap
use and large application performance remain unprofiled.

Initial limitations were explicit in the template guide: an HTML fragment subset,
field-path expressions, one generated root namespace, no nested loops, component
composition, raw HTML injection, or full Scripty evaluation. The compiler rejects
unsupported syntax instead of silently falling back to an interpreted renderer.

## Composed application controls follow-up

Generated `Scoped` projections coexist in
one root with explicit ID ranges, including keyed descendants. Compiler tests
also reject overlapping and invalid range assignments.

The next slice adds explicit table/select structure and SVG semantics. The demo
composes the main template and two instances of `controls.gui.html`. Native tests
cover malformed browser-repaired structures, select leaf-only patches, unsafe
initial SVG references, lossy option/control values, namespace overflow and
optional reference removal. The browser exercises controlled selection, option
removal/restoration, retained table drafts/focus, SVG namespace and insertion,
sprite changes, unique IDs, recovery, teardown and memory growth.

`npm test` and `npm run test:browser` pass; the latter runs four browser tests.
Desktop/mobile screenshots were inspected, including the composed panels; no
mobile horizontal overflow was detected. The current composed demo is 51,651
WASM bytes with two initial pages, including its 64 KiB stack. Scratch/output
buffers are 16 KiB each and the maximum admitted state passes full recovery.
These measurements include additional example behavior and are not a frontend
performance guarantee.

See the [framework roadmap](roadmap.md) for planned capabilities. Nested loops,
template invocation syntax and large-application profiling remain deferred.
