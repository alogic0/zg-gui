# Extraction boundary

Initial rendering-core boundary, September 14, 2026.

| Source | Extracted module | Adaptation |
| --- | --- | --- |
| `src/ui/html.zig` | `src/html.zig` | Bounded escaped writer and tests |
| `src/ui/patch.zig` | `src/patch.zig` | Protocol, escaping, ranges; application enums removed; named inputs |
| `src/ui/render/surface.zig` | `src/projection.zig` | Leaf snapshots and structural/keyed lists; named inputs |
| `web/runtime/wasm-bridge.js` | `web/dom.js`, `web/runtime.js` | Generic DOM commands and UTF-8 exchange; provider/session integrations removed |
| `web/runtime/local-datetime.js` | `web/local-datetime.js` | Browser-local formatting |
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
