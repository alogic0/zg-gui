# Shared browser startup

Use one framework dependency for the Zig API and the browser runtime. Applications
can own only Zig, templates, HTML and CSS; the build installs the shared JavaScript
and a finite manifest. Existing `mount`, `load` and `createApp` remain available
for integrations that need their own lifecycle.

## Build and HTML

Configure a freestanding wasm32 artifact with exported memory and the ordinary
runtime ABI, then call this public build helper:

```zig
@import("zg_gui").addWebApp(b, .{
    .dependency = gui,
    .artifact = app,
    .features = .{ .browser = true, .math = false, .prepaint = true },
});
```

The helper adds installation steps for `web/<artifact-name>.wasm`,
`web/app.json` and `web/gui/`. The generated manifest is version 1:

```json
{"version":1,"wasm":"./counter.wasm","browser":true,"math":false}
```

The six core modules are runtime, DOM host, node registry, local date/time input,
startup and auto-start. Browser requests, math surfaces and pre-paint styling are
separately selected. A fresh installation contains only selected modules; worker
transport is outside this helper. A reused installation may retain old files.
Use a fresh deployment directory or explicitly clean obsolete generated assets.
The helper does not install project HTML/CSS, configure native math providers,
choose application actions, or alter the artifact's native ABI/stack settings.
It currently installs one application manifest per prefix.

Consumer HTML supplies the root, manifest URL and initial/error presentation:

```html
<div id="app" data-zg-app="./app.json"
     data-zg-error="The application could not start." aria-busy="true">
  Loading…
</div>
<script type="module" src="./gui/auto-start.js"></script>
```

The auto-start module starts declared roots independently. Manifest/WASM URLs
must use same-origin HTTP(S), without credentials, fragments or redirects. WASM
URLs in a manifest resolve relative to that manifest; direct startup URLs resolve
relative to the document. Manifest admission rejects unknown fields, wrong
types/versions and more than 4096 UTF-8 bytes. The size limit applies after the
response body is received; it is not a streaming network limit.

Do not maintain copied runtime source in applications. Pin the framework
dependency and toolchain for reproducible builds, and install Zig and JavaScript
from that same revision. Each deployment receives its selected assets; a shared
CDN or cross-site browser-cache scheme is not required.

## Public lifecycle API

Import `start`, `getApp`, or `startDeclaredApps` from `zg-gui/startup` or the
installed `gui/startup.js` module:

```js
const app = await start({root, manifest:'./app.json'});
// Or: start({root, url:'./counter.wasm', browser:true, math:false});
// Or: start({root, wasm:instance.exports, browser:true});
app.dispatch({action:1});
app.dispose();
```

`start` owns one connected HTML root and a fresh native instance, including native
exports supplied by the caller. Duplicate ownership fails while starting or
mounted. Optional `imports` are available for programmatic instantiation. The
manifest form excludes direct native/URL/capability options. Browser capability
requires the optional native host-event ABI; math requires declared surfaces.
The shared startup uses main-thread execution.

`getApp(root)` returns the ready owner or undefined. `startDeclaredApps` scans
current `data-zg-app` roots, waits for any already starting owner, and returns an
array of ready apps or undefined for failed roots. It reports failures through
`onError` and lets other roots start. No application globals or DOM observers
are installed. Auto-start scans once; dynamically added roots need another call.

The root has `data-zg-status` loading, ready, error or disposed. Loading sets
`aria-busy`; readiness/failure/disposal clear it. Readiness dispatches a
non-bubbling `zg:ready` event on the root with the app in `event.detail`.
If startup fails, `data-zg-error` optionally supplies plain fallback text. Styling
and wording remain consumer-owned. `onError` defaults to console reporting and
should not throw.

The owner includes the ordinary dispatch/input/host-event APIs, native `wasm`
exports, selected `features`, `initialMemoryBytes`, `diagnostics()` and
`resources()`. Diagnostics retain the last 32 entries; resources include the total
error count and optional host counters. Disabled math reports zero surface/work
counters. This is introspection, not an application controller.

Startup synchronizes math then browser requests after each completed projection.
Browser events use deferred native delivery. Failure or idempotent disposal
releases browser and math hosts, calls optional native `deinit` once, and disposes
the GUI owner. Every cleanup is attempted even if another throws. Queued callbacks
are suppressed and the root can be remounted with a new instance. Disposal leaves
the last DOM in place. Startup returns its owner after initialization; cancelling
an in-flight fetch before an owner is returned is outside this version.

## Optional pre-paint presentation

Select `.prepaint = true` and place the shared classic script before styles:

```html
<script src="./gui/prepaint.js" data-zg-theme-key="sample.theme"
        data-zg-theme-default="system"></script>
```

The key uses 1–128 ASCII letters/digits/underscore/hyphen/dot. Fallback accepts
light, dark or system; only exact saved light/dark values affect presentation.
Storage failure falls back without preventing display. This script sets document
theme only and installs no listeners or globals. Initialized theme policy and
ongoing preference behavior stay in Zig. Consumers coordinate document-wide theme
ownership when mounting multiple roots.

The [declarative example](../examples/web/startup.html) uses shared startup with
an existing native module and no example JavaScript. Provider checks and source
sizes are recorded in [request 085](requests/085-shared-browser-startup.md).
Application measurements and acceptance belong to consumers.
