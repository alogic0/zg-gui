# zg-gui

A standalone Zig/WASM GUI core. Zig owns state,
rendering decisions, and stable node IDs. A small JavaScript host applies the
typed DOM stream and forwards declared actions and inputs.

Includes bounded escaped HTML, leaf snapshots, structural and keyed child
lists, text/attribute/form/focus/move patches, browser validation, UTF-8 exchange,
and mount/dispose lifecycle. Runtime dependencies: a browser and WebAssembly.
Playwright is only a development dependency.

Use the exact compiler in `.zigversion` (the source project's installed snapshot).

```sh
zig build test
npm ci
npm test
```

For browser tests, install Chromium with `npx playwright install chromium` if
it is not already available. Tests run headlessly and require no backend.

The extraction is an independent repository. The original application continues
to use its existing implementation. See [provenance](docs/extraction.md).
