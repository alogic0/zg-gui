# Request 064: Web Component Custom Elements Interop (<zg-view>)

Status: implemented; autonomous custom element registration `<zg-view>` with optional Shadow DOM encapsulation, attribute reflection, and lifecycle cleanups.

## Reusable Problem

Modern web architectures and microfrontends frequently require embedding components into host frameworks (e.g. React, Angular, Vue, or vanilla legacy applications) without leaking styles or conflicting with host DOM listeners:
1. **Host Boundary Isolation**: Embedding template trees directly into third-party DOMs risks global stylesheet interference and unintended class collisions.
2. **Lifecycle Synchronization**: Host frameworks create, move, and remove DOM nodes dynamically; `zg-gui` instances must automatically mount, disconnect, clean up timers/observers, and abort exit transitions when removed from the DOM.
3. **Encapsulated Patch Streaming**: External hosts need a standard, vendor-neutral web component (`<zg-view>`) that exposes methods to stream binary or text patches directly to an encapsulated Shadow Root or Light DOM child.

## Required Contract

1. **Autonomous Custom Element Definition**:
   - Register `<zg-view>` as a standard Web Component:
     ```html
     <zg-view shadow="open" data-template="overview"></zg-view>
     ```
   - Attributes:
     - `shadow`: `"open"` or `"closed"` for Shadow DOM encapsulation; omit or set to `"none"` for Light DOM.
     - `src` / `data-stream`: Optional attribute or property for initial snapshot payload.
2. **DOM Bridge Integration**:
   - `zg-view` instantiates an internal `createDomHost` rooted at its Shadow Root or element body.
   - Exposes public JavaScript methods:
     - `initialize(html, options)`: Hydrates or initializes the view tree.
     - `applyPatchStream(stream)`: Applies incoming text or binary patches.
     - `dispose()`: Cleans up listeners, aborts exit transitions, and forgets node mappings.
3. **Lifecycle Management**:
   - `connectedCallback()`: Attaches event listeners and prepares the DOM container.
   - `disconnectedCallback()`: Calls `dispose()` to prevent memory leaks, cancels pending animation frames, and releases event handlers.
4. **Zero Runtime Heap Allocation**:
   - Zig models remain unchanged, continuing zero-heap patch generation; custom element encapsulation is purely a boundary adapter.

## Acceptance Checklist

- [x] Specify neutral capability contract for `<zg-view>` custom element.
- [x] Implement `<zg-view>` custom element definition in `web/dom.js`.
- [x] Provide Shadow DOM encapsulation and Light DOM modes.
- [x] Verify lifecycle mounting, patch streaming, and disposal across Chromium and Firefox.
