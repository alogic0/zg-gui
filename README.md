# zg-gui

A compact Zig/WebAssembly GUI framework with HTML-like templates compiled into
Zig. Application state and rendering decisions live in Zig; a small JavaScript
host applies precise DOM updates and forwards declared events.

**Small updates. Steady controls.** Keyed rows, editable forms, and focused inputs
keep their DOM identity across updates and reordering.

![Fieldwork: the zg-gui project workspace](docs/images/workspace-desktop.png)

[Watch the interaction demo](docs/images/workspace-demo.webm) ·
[Mobile screenshot](docs/images/workspace-mobile.png) ·
[Dark theme](docs/images/workspace-dark.png) ·
[Source walkthrough](docs/workspace-showcase.md)

## Try the workspace

Use the exact Zig compiler in [`.zigversion`](.zigversion). Builds also require a
sibling `zig-cdp` checkout at `../zig-cdp`, as configured in `build.zig.zon`.
Then:

```sh
npm ci
npm run dev
```

Open **http://127.0.0.1:4180**. Stop the server with Ctrl+C.

Fieldwork is a complete, synthetic project workspace. Edit task names and notes,
change status and priority, assign teammates, search, filter, sort, reorder, add
and delete tasks. Progress, an SVG status chart, and recent activity update from
the same Zig state. Light/dark themes and a responsive layout work on desktop
and mobile. Use **A− / A+** in the top bar to adjust text size from 80% to 140%.
The three overview cards share one compiled template component.

No account, backend, external assets, or runtime npm dependencies. Workspace
changes survive page navigation and reloads within the same browser tab.
**Reset demo** restores the sample. Your theme preference is saved across
Showcase, Basics and Source. The example holds up to 24 tasks. Open **How this demo works** for a quick explanation and a
source walkthrough. Use the shared **Showcase / Basics / Source** navigation
on any screen size. The introductory **/basics.html** demo includes guided
experiments for live inputs, retained rows and independent component choices.

## A template, a typed view, a small host

```html
<input :value="$name" :input="$inputs.name">
<ul :loop="$rows" :key="id" :limit="24">
  <li><span :text="$item.label"></span></li>
</ul>
```

The native compiler validates templates and generates stable identities and typed
projection code. The browser receives escaped initial HTML, followed by text,
attribute, form-value, focus, and structural commands. There is no runtime
template parser or virtual DOM.

- Caller-owned, bounded HTML and patch buffers with explicit failure admission.
- Property snapshots and keyed child lists with retained row identity.
- Reusable template components, scoped namespaces, and typed child slots.
- Controlled inputs/selects, SVG, table fragments, and numeric CSS variables.
- UTF-8 exchange, mount/dispose lifecycle, and explicit recovery after bad patches.

Start with the [template guide](docs/templates.md),
[integration and ownership](docs/integration.md), and
[command protocol](docs/protocol.md). The [roadmap](docs/roadmap.md) documents
capabilities and limits, including unsupported nested keyed loops and multiple
selection. Consumer state, effects, routing, styling, and application policy
remain outside the framework.

Optional [diagram projections](docs/diagrams.md) add flowcharts, sequence diagrams
and SVG export through a caller-selected layout engine. Run
`zig build serve -Ddiagrams=true` and open **http://127.0.0.1:4180/diagrams.html**
for the two-source example. Core-only builds keep the engine dependency unused.

## Explore the example

| File | Responsibility |
| --- | --- |
| [workspace.zig](examples/workspace.zig) | Owned state, validation, view derivation, actions, ABI, native tests |
| [workspace.gui.html](examples/workspace.gui.html) | Workspace layout, forms, keyed task and activity lists |
| [workspace-metric.gui.html](examples/workspace-metric.gui.html) | Reusable summary card and SVG status chart |
| [workspace.css](examples/web/workspace.css) | Responsive layout, visual design, themes |
| [workspace.js](examples/web/workspace.js) | Loading the public browser runtime |
| [workspace.test.mjs](tests/workspace.test.mjs) | Real WASM/browser journeys, identity, focus, limits and measurements |

`zig build` produces the complete static site in **zig-out/web**. All application
assets use relative paths, including beneath a repository subpath. See the
[showcase guide](docs/workspace-showcase.md) for hosting and reproducible checks.

## Verify

For native Zig browser automation, see the [CDP README](tools/lib/README.md).
It covers launching Chrome, page actions, screenshots, and owned cleanup.

```sh
npx playwright install chromium
npm test
npm run test:browser
```

`npm test` runs native, compiler, independent-package, and host tests, including
the workspace. The browser suite exercises both examples, recovery, retained DOM
objects, focus, selection, desktop/mobile layout, and generated-template edge
cases. Playwright is a development dependency only.

The [showcase guide](docs/workspace-showcase.md#measurements) records artifact
size, memory, and representative patch work. These are example measurements,
not consumer budgets or peak-memory guarantees.

Framework changes follow [neutral capability requests](docs/contributing.md).
Provider verification and consumer application acceptance remain separate.
