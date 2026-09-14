# Extraction boundary

Initial rendering-core boundary, September 14, 2026.

| Source | Extracted module | Adaptation |
| --- | --- | --- |
| `src/ui/html.zig` | `src/html.zig` | Bounded escaped writer and tests |
| `src/ui/patch.zig` | `src/patch.zig` | Protocol, escaping, ranges; application enums removed; named inputs |
| `src/ui/render/surface.zig` | `src/projection.zig` | Leaf snapshots and structural/keyed lists; named inputs |
| `web/runtime/wasm-bridge.js` | `web/dom.js`, `web/runtime.js` | Generic DOM commands and UTF-8 exchange; provider/session integrations removed |
| `web/runtime/local-datetime.js` | `web/local-datetime.js` | Browser-local formatting, including directly appended controls |
| `web/runtime/rendering.js`, `delegated-interactions.js` | `web/runtime.js` | Reduced generic mount, resync, actions and form inputs; explicit teardown added |

No backend, credentials, customer fixtures, fonts, icons, or vendor code were
copied. Consumer repositories are outside the framework boundary.
No license is assigned here; extraction does not grant publication rights.

This is the reusable rendering core, not an Electron replacement or a full
widget catalog. Desktop windows, packaging, native APIs, routing, persistence,
provider effects, application layouts, navigation and modal policy remain
outside this package. Product UI code still needs deliberate generalization
before it can join the framework. Styles and the example belong to this package.

The command format remains compatible with the generic subset of the source
protocol, but Zig call signatures intentionally use named inputs. Application-specific
node IDs, provider exceptions, and application ABI exports are omitted.
The extracted host additionally rejects unsafe link protocols and self moves.

## Verification on September 14, 2026

Completed using the pinned compiler and local headless Chromium:

- `zig build test`: core and example tests, including leaf-only counter patches,
  structural membership, retained keyed rows, JSON control characters, snapshot
  overflow, invalid input, and maximum escaped input through full resync.
- `npm test`: native tests, local datetime unit test and DOM protocol browser test.
- `npm run test:browser`: ReleaseSafe WASM build and three browser tests. Checks
  retained object identity, focus and selection; controlled inputs; checkbox and
  theme; disclosure; row append/remove/reorder; overflow refusal; root ownership;
  explicit disposal/remount; missing-target recovery; and fresh memory views.
- Desktop (1280 px) and mobile (390 px) screenshots visually inspected; no page
  or console errors on the normal journey, no horizontal overflow on mobile.
- Temporary independent Zig package: imported the exported `zg_gui` module via
  a relative path dependency, built and tested a typed text patch. Files removed
  after the check. The documented relative path is required by Zig.
- `git diff --check`: passed. Framework changes were verified independently.

Measured example: 25,255-byte WASM, two initial 64 KiB pages; the memory-growth
test adds one page. No allocator is used by the core/example, and these numbers
do not establish a peak-memory or large-application performance claim.
Screenshots are reproducible outputs in ignored `test-results/`.
