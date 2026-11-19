# External CDP dependency

Implemented October 24, 2026. Verified with `zig-cdp` 0.5.2 on November 19, 2026.

Native browser tools need one maintained CDP implementation that Zig can fetch
from a clean checkout. Pin the public `zig-cdp` Git revision and package hash
in `build.zig.zon` and use its public `cdp` build module.

Keep the framework's public `cdp` module available to existing consumers. Native
tool tests and browser suites import that same module. It runs on the build host
with debug optimization. WebAssembly framework targets use the GUI module.

The browser harness owns an arena and an owned headless browser with a private
profile and ephemeral debugging port. Per-test raw sessions own their targets,
sockets and allocations. Closing the last session stops the browser and preview
server, then releases the arena within the owning test's allocator lifetime.
Startup failures must release partially acquired resources. Browser launch,
protocol and dependency resolution failures remain visible to callers.

Build the framework from an empty package cache with only its source tree
present. Run native tool integration tests, the browser suite with its DOM
identity and focus assertions, and the core and template checks. Build and run
the public `cdp` module example from a separate package. The dependency owns
its protocol tests. These checks cover framework integration.

## Verification

On Linux with Zig 0.17.0, `zig build -j4` fetched the pinned packages into an
empty cache and built the framework. `zig build test-all -j4 --summary all`
passed all 318 tests, including 8 native tool tests and 70 browser tests.

A separate package fetched a source archive of the framework and ran the
[documented example](../../tools/lib/README.md#run-a-complete-example) through
`gui.module("cdp")`. It started an owned Chrome session, filled the form,
checked its result, and wrote a PNG screenshot.
