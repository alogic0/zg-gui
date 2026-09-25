# Cross-engine browser contract verification (Chromium & Firefox)

Status: implemented and provider verified; consumer acceptance is separate.

The framework development strategy establishes Priority 1 and Stage 5
milestones requiring DOM command streams, state retention, controlled inputs,
and focus mechanics to be verified across independent browser engines rather
than Chromium alone.

`tests/browser.mjs` now supports configurable browser engines via the
`ZG_BROWSER` environment variable (`chromium`, `firefox`, `webkit`).

Optimized test harness:
- Single browser lifecycle: `before` and `after` test hooks instantiate the
  shared HTTP server and browser process once per test suite rather than per
  test, eliminating redundant cold-start profile overhead.
- Isolated test contexts: each test executes within an independent `page`
  context and disposes it on teardown.
- Verified on Gecko: the complete standalone WASM application suite (state,
  DOM identity, selection ranges, focus, theme toggle, counter transitions,
  disposal, error resynchronization, table rows, SVG namespaces, and controlled
  select values) runs and passes 100% on Firefox.
- Multi-engine scripts: `package.json` adds `test:browser:firefox` and
  `test:browser:all`.

Verification: all 3 test scenarios in `tests/browser.mjs` pass under both
Chromium (1.17s) and Firefox Gecko.
