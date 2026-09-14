# zg-gui

A standalone Zig/WASM GUI core. Zig owns state,
rendering decisions, and stable node IDs. A small JavaScript host applies the
typed DOM stream and forwards declared actions and inputs.

Includes bounded escaped HTML, leaf snapshots, structural and keyed child
lists, text/attribute/form/focus/move patches, browser validation, UTF-8 exchange,
and mount/dispose lifecycle. Runtime dependencies: a browser and WebAssembly.
Playwright is only a development dependency.

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
interaction and recovery tests, and desktop/mobile screenshots. The example's
WASM is 25,255 bytes and starts with two 64 KiB memory pages, including a 64 KiB
stack. These are example measurements, not a budget for other applications;
peak stack/heap use has not been profiled. Screenshots are generated under
ignored `test-results/` by the browser test command.
