# External CDP dependency

Status: implemented and verified, October 24, 2026.

Native browser tools need one maintained CDP implementation supplied by a Zig
package dependency, rather than a bundled protocol client and journey runtime.
Use the sibling `zig-cdp` package through its public `cdp` build module.

Keep the framework's public `cdp` module available to existing consumers. Native
tool tests and browser suites import that same module. The dependency runs on
the build host with debug optimization; WebAssembly framework targets do not
import it. Configure the local package through `build.zig.zon`.

The browser harness owns an arena and an owned headless browser with a private
profile and ephemeral debugging port. Per-test raw sessions own their targets,
sockets and allocations. Closing the last session stops the browser and preview
server, then releases the arena within the owning test's allocator lifetime.
Startup failures must release partially acquired resources. Browser launch,
protocol and dependency resolution failures remain visible to callers.

Acceptance checks: run native tool integration tests and the browser suite
against the external module, retain DOM identity/focus assertions, run the core
and template checks, and verify the public module from a separate package.
Remove the bundled implementation and update setup commands to use package
integration. CDP implementation tests belong to the dependency; local fixtures
remain finite integration evidence. No browser feature, GUI behavior, performance
or memory-budget change is requested.

Verification: `zig build test-tools -j4 --summary all` passed all seven local
integration tests. `zig build test-browser -j4 --summary all` passed all 58
browser tests, including DOM identity and focus assertions. `zig build test -j4
--summary all` passed the core/template/workspace/tool gate (52 freshly executed
tests, with other test runs cached). A temporary independent package imported
`dependency.module("cdp")`, started an owned browser, evaluated a page expression,
and closed its page/browser successfully. Touched Zig sources were formatted
and `git diff --check` passed. These checks establish local package integration,
not exhaustive CDP behavior or consumer application acceptance.
