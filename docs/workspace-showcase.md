# Fieldwork workspace example

The default example is a synthetic project-planning workspace. Its purpose is to
make the framework's capabilities inspectable through a complete small app.
There are no customer records, backend services, authentication, or persistent
task storage. Only the appearance preference is saved in browser localStorage.
The original introduction is still available at `/basics.html`.

## Run and explore

Use the compiler in `.zigversion`, run `npm ci`, then `npm run dev`. Open
http://127.0.0.1:4180. Try the following journey:

1. Click anywhere on a task row to select it and edit its name or notes in the
   detail panel. The completion button only toggles completion; the task title
   remains the keyboard entry point.
2. Change its status, priority, or assignee. The row, progress and activity update.
3. Use the arrow buttons to reorder the selected task. Reordering returns the
   list to manual order, including when it was previously sorted.
4. Search by task name or identifier, or choose a status filter. Filtering removes
   excluded row DOM objects; their data stays in Zig and their rows return when
   the filter clears. The selected editor remains available even if its task is
   filtered out.
5. Add a task. Search and status filters clear so the new task is visible, and the
   editor receives focus. Delete it or reset the sample when finished.
6. Use A− / A+ in the top bar to adjust all workspace text from 80% to 140%
   in 10% steps (default 100%). Switch themes and resize to a mobile viewport.
   Task selection brings the editor heading into view on narrow screens.
   **Back to tasks** returns focus to the selected row, or search if a filter
   hides that row. Native details disclosure opens the implementation notes.

Task changes are session-only. Reload discards them. The theme persists across
Showcase, Basics and Source, including reloads. Reset restores the tasks and
activity while retaining the chosen theme and font size. The sample accepts at
most 24 tasks; creation disables at capacity, and the status message explains
how to continue.

## Basics and source navigation

Showcase, Basics and Source links remain visible at every supported width. The
Basics page walks through live input, count updates, retained rows and independent
component instances. Each experiment links to an explanation and source downloads.
Reverse rows reverses the entire visible list and both mapping tables; toggling a
third row does not change channel options. The separate Remove Email option
experiment explains unavailable selections and restores them when Email returns,
unless the visitor chose SMS instead. Removing a row discards its browser-only
draft. Retained rows keep their drafts.

## Code and ownership

- [workspace.zig](../examples/workspace.zig) owns fixed task/text/activity storage,
  state transitions, validation, filtering, sorting, metrics, and projection.
- [workspace.gui.html](../examples/workspace.gui.html) declares the layout,
  controlled forms, keyed task rows, and a bounded activity list.
- [workspace-metric.gui.html](../examples/workspace-metric.gui.html) is invoked
  three times with independent typed views. One instance includes a derived SVG
  distribution of to-do, active, and completed tasks.
- [workspace.js](../examples/web/workspace.js) loads the public runtime and owns
  mobile viewport navigation and focus return. It leaves task state in Zig and
  removes its listeners on disposal. The example-only `window.workspace` handle
  exposes public runtime methods for tests.
- [demo-theme.js](../examples/web/demo-theme.js) restores the saved theme before
  painting and synchronizes each Zig example through public dispatch. Storage
  failure leaves local theme controls usable. Its observers and listeners are
  released with the example; Source uses the same preference and control.
- [workspace.css](../examples/web/workspace.css) owns presentation and responsive
  behavior. Both examples share navigation and theme tokens in
  [demo-shared.css](../examples/web/demo-shared.css). No network fonts, third-party
  images, or CSS frameworks are used.

Text fields own their bytes. Titles/search use 192-byte buffers, notes use 1,024
bytes, and exchange capacity is 2,048 bytes. The browser limits titles/search to
48 UTF-16 units and notes to 256; valid text at those limits fits the UTF-8 buffers.
Admission checks also reject invalid UTF-8 and excess bytes at the WASM boundary.
Search folds ASCII case; other UTF-8 characters match exactly.

Candidate state, next snapshot, and complete output commit together only after
both bounded writers succeed. Rendering uses two 128 KiB static buffers, derived
snapshot capacity plus one focus entry, and a 512 KiB WASM stack reservation.
There is no runtime allocation. Task keys stop before 10,000; the five-entry
activity history uses a bounded rolling key sequence. Actions and input kinds
are internal example conventions, not new framework APIs.

## Checks

```sh
zig build test-workspace
npm test
npm run test:browser
```

Native coverage includes state updates, invalid/oversized UTF-8 input, filtering,
creation/deletion and font-size limits, scalar/move patch shape, and maximum
escaped text at full task capacity followed by recovery. Browser journeys use
the real WASM module and assert row/ancestor/control identity, focus and
selection retention, empty states, form updates, sorting, reordering, activity,
reset, mobile editor navigation, theme persistence, whole-row selection,
font-size keyboard controls and narrow layouts at 140%, and assets
beneath a repository subpath.

The tests write desktop, mobile, and dark screenshots beneath ignored
`test-results/`. Reviewed presentation captures and the short interaction video
are checked in under [images](images/). The video demonstrates editing, status
changes, reorder, filtering, creation, and dark theme.

## Measurements

See the recorded verification in
[request 042](requests/042-interactive-workspace-showcase.md). The artifact test
prints the exact built WASM size, initial/observed linear memory, initial HTML
length, and representative reorder command count/bytes. Observed linear memory
is not a peak stack/heap profile, and native/browser test success is not consumer
application acceptance.

## Static hosting

`zig build` installs a self-contained site in `zig-out/web`, including the WASM
modules, host, styles, icon sprites, basics example, source walkthrough, and
source downloads. Serve that directory locally with `npm run dev` or upload its
contents to a static host configured for the intended repository/site.

No repository remote or public deployment destination is configured in this
checkout, so the showcase is prepared locally without a fabricated live URL.
