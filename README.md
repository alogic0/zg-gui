# zg-gui

A standalone Zig/WASM GUI core with HTML-like templates compiled into Zig.
Zig owns state and rendering decisions. A small JavaScript host applies the
typed DOM stream and forwards declared actions and inputs.

Includes bounded escaped HTML, leaf snapshots, structural and keyed child
lists, text/attribute/form/focus/move patches, browser validation, UTF-8 exchange,
and mount/dispose lifecycle. Runtime dependencies: a browser and WebAssembly.
Playwright is only a development dependency.

Write layouts in [HTML templates](examples/demo.gui.html), with bindings such
as `:text="$count"` and `:on-click="$actions.increment"`. The native compiler
generates stable node IDs and projection code during the build. Application
state, derived view values and actions stay in [Zig](examples/demo.zig).
See the [template language and build guide](docs/templates.md).

Use the exact compiler in `.zigversion`.

```sh
cd ~/prog/zg-gui
zig build test
npm ci
npm test
npm run test:browser
npm run dev
```

The last command builds and serves the example at `http://127.0.0.1:4180`.
It demonstrates controlled text and checkbox inputs, a theme, a counter,
disclosure visibility, and keyed rows that retain their browser drafts and focus.
Press Ctrl+C to stop the development server.

For browser tests, install Chromium with `npx playwright install chromium` if
it is not already available. Tests run headlessly and require no backend.

For another application, import the `zg_gui` Zig module and host it with
`web/runtime.js`. See the [integration and ownership guide](docs/integration.md),
the [command protocol](docs/protocol.md), and the working [example](examples/demo.zig).

Verified locally: native core/example tests, a ReleaseSafe WASM build, Chromium
interaction and recovery tests, and desktop/mobile screenshots. The composed example's
WASM is 51,651 bytes and starts with two 64 KiB memory pages, including a 64 KiB
stack. These are example measurements, not a budget for other applications;
peak stack/heap use has not been profiled. Screenshots are generated under
ignored `test-results/` by the browser test command.

The demo also composes two [integration panels](examples/controls.gui.html) with
SVG icons, keyed table rows and controlled selects. See the
[framework roadmap](docs/roadmap.md) for available and planned capabilities.

Framework work follows [neutral capability requests](docs/contributing.md).
Consumer integration and product acceptance remain outside this repository.
