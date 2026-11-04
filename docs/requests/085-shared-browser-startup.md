# Shared browser startup and asset installation

Status: implemented and verified with neutral native/WASM browser fixtures.

## Contract

Independent Zig/WASM applications need one reusable browser entry point and
lifecycle owner. Consumers should declare a WASM asset and optional browser/math
capabilities without writing fetch, mount, synchronization or disposal code.
Application state, actions, content, routing, styling and policy remain in Zig
and consumer assets. Existing low-level runtime APIs remain supported.

Provide public `start` and `getApp(root)` APIs, plus a declarative auto-start
module. A root's `data-zg-app` names a same-origin manifest. The finite version-1
manifest declares only a WASM URL and boolean browser/math capabilities. Admit
at most 4096 UTF-8 bytes; reject unknown fields, invalid versions/types and
non-HTTP(S) or cross-origin manifest/WASM URLs. No arbitrary module names, action
IDs, expressions, code, selectors or application globals belong in the manifest.

Reserve a root while startup is pending. Duplicate ownership fails. Instantiate
one module per root, synchronize optional hosts after completed projections and
deliver browser events through the existing optional host-event ABI. Import
optional hosts only when enabled. Startup owns supplied native exports until
disposal, including optional `deinit`. Release adapters, native allocations and
runtime listeners on failure or idempotent disposal; suppress queued callbacks.
Expose readiness through root status/aria-busy and a root-scoped ready event.
Bound retained diagnostics to 32 entries and expose resource counters.

A public Zig `addWebApp` helper installs the selected WASM, generated manifest
and required shared modules into an application installation. Optional modules
are explicitly selected and absent from a fresh core installation. Project HTML
and CSS remain consumer-owned. Runtime changes come from the selected framework
dependency; do not copy a separately maintained runtime into consumer sources.
Existing unrelated files in a reused installation are not automatically deleted.

A shared optional classic pre-paint script accepts a bounded preference key and
light/dark/system fallback through script data attributes. It only paints the
document before WASM loads. Initialized preference policy remains consumer-owned.

## Acceptance

- [x] Neutral browser checks cover real WASM startup, retained DOM/focus, distinct
      roots, optional host ordering, startup failures, disposal and remount.
- [x] Manifest admission, duplicate ownership, failed native initialization and
      queued-callback cleanup have meaningful failure checks.
- [x] A declarative example uses no project-specific JavaScript.
- [x] Public build/API documentation, selected asset sizes, and relevant full
      host/compiler checks are recorded separately from consumer acceptance.

This contract centralizes maintained JavaScript. It does not claim globally
minimal transfer size, add a bundler or optimize existing DOM commands. Worker
startup and further platform capabilities remain separate work.

## Verification and cost record

See [the public startup API](../browser-startup.md).
`zig build test-browser -Dbrowser-filter='shared startup'` passes three selected
tests. The neutral fixture uses real native WASM, tests retained input/count DOM
and focus, independent instances, remount, and no optional module requests in a
core page. Failure checks cover strict manifest admission, duplicate startup,
bounded diagnostics, missing optional ABI, native initialization failure, and
failure after allocating a frame and queuing a preference event. Cleanup releases
both adapters, native ownership and GUI listeners; no stale events are delivered.
`zig build test-all -Ddiagrams=true --summary all` passes all 122 steps with 192
freshly executed tests and remaining checks cached.

The six shared core modules total 60,984 uncompressed source bytes. Shared
startup and auto-start contribute 5,719 and 78 bytes. Optional browser/math hosts
add 8,942/7,097 bytes and pre-paint adds 703 bytes. Disabled modules are not
requested by the core fixture. These are source bytes, not compressed transfer
or JavaScript heap measurements. The loader records initial native linear
memory, while peak memory and DOM/browser patch traffic remain consumer-specific
measurements. Startup has no new native allocation ABI. Host disposal reaches
zero owned records/handles and diagnostics retain at most 32 entries.
Provider success does not establish application acceptance or a performance
budget; consumer adoption is tracked separately.
