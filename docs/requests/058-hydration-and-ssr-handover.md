# Request 058: Hydration and SSR-to-WASM handover

Status: implemented and verified.

## Reusable problem

In modern web applications, pre-rendering HTML on the server or during static build time (via `renderHtml`, Request 050) is essential for rapid initial content display (First Contentful Paint), SEO, and accessibility.

However, when the client-side WebAssembly module finishes downloading and initializes, the runtime (`runtime.js`) currently calls `dom.initialize(projection)`, which assigns `root.innerHTML = toText(html)`. This operation:
1. **Destroys and Recreates the DOM**: Discards all existing DOM nodes that the browser has already parsed, styled, and rendered.
2. **Visual Flashing & Layout Shifts**: Causes layout reflows and visual glitches (e.g. flickering iframes, resetting image decodes).
3. **Loss of Early User Input**: If a user began typing in an input field or scrolled down the page before WASM finished downloading, assigning `innerHTML` obliterates their focused element, caret position, and draft text.

This request delivers non-destructive **Hydration**: seamlessly adopting the existing server-rendered DOM elements, attaching node IDs and event listeners into the node registry without re-creating nodes, and preserving user drafts and focus.

## Required contract

1. **Non-Destructive Node Registry Adoption**:
   - When `hydrate: true` is passed (or when `root` contains matching `[data-node-id]` elements upon boot), `dom.hydrate(html)` (or `dom.initialize(html, { hydrate: true })`) does NOT assign `root.innerHTML`.
   - Instead, the DOM host traverses the existing DOM tree, binds all elements with `data-node-id` into the node registry, and hooks into `MutationObserver`.
   - Existing element references (`HTMLElement`, `HTMLInputElement`, etc.) remain identical in memory before and after WASM boot (`existing === document.querySelector(...)`).

2. **Attribute & Value Synchronization Without DOM Rebuild**:
   - The DOM host synchronizes declared dynamic attributes (classes, styles, accessibility flags, selected options) onto the existing elements.
   - For form controls (`<input>`, `<textarea>`, `<select>`):
     - If the element is currently focused (`document.activeElement === target`) and the user has typed an uncommitted draft, the user's active draft and caret selection are strictly preserved.
     - Select elements reconcile controlled option values via `applySelectValues()`.
     - Declared style variables are applied via `applyDeclaredStyles()`.
     - Local instant timestamps are formatted via `applyInitialTimeFormats()`.

3. **Discrepancy Reconciliation & Fallback**:
   - If the pre-rendered DOM contains a structural mismatch (e.g. missing required node ID anchors or corrupted markup), the host cleanly falls back to a full initialization (`root.innerHTML = ...`) and notifies `onError`.
   - If server and client initial projections differ only in dynamic values (e.g. client timezone difference), the host applies surgical leaf updates without tearing down the parent tree.

4. **Unified Consumer API**:
   - `mount({ root, wasm, hydrate = false })`
   - `load({ root, url, hydrate = false })`
   - `createApp({ root, wasmUrl, hydrate = false, worker = false })`
   - If `hydrate: true` (or `{ hydrate: 'auto' }`), the host automatically hydrates if `root.firstElementChild` exists and has `data-node-id`, else performs standard clean initialization.

## Acceptance checklist

- [x] Specify hydration contract and auto-detection behavior.
- [x] Implement `hydrate()` in `web/dom.js` adopting existing DOM elements into the node registry.
- [x] Support `hydrate` option in `web/runtime.js` (`mount`, `load`, `createApp`) and `web/worker-host.js`.
- [x] Verify identical DOM node identity retention (`prevNode === nextNode`) after hydration.
- [x] Verify focus retention and draft preservation for inputs active during hydration.
- [x] Verify graceful fallback to full render when pre-rendered markup is malformed or mismatched.
- [x] Add browser tests exercising hydration over SSR-rendered templates (Chromium & Firefox).
- [x] Ensure 100% test pass across `zg-gui` without regressions.
