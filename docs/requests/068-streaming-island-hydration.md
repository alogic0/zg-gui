# Request 068: Streaming Island Hydration (:hydrate="visible|idle")

Status: implemented; declarative island hydration boundaries deferred by visibility or thread idleness.

## Reusable Problem

Full-page synchronous SSR hydration forces the browser to traverse, bind, and initialize listeners across every DOM element upfront:
1. **Total Blocking Time (TBT)**: On content-heavy pages with offscreen tables, complex dialogs, or deep lists, upfront hydration delays interactive response to critical user inputs.
2. **Wasteful Hydration**: Users frequently do not interact with below-the-fold or collapsed subtrees; hydrating them immediately wastes battery and CPU.
3. **Coordinated Activation**: Isolated subtrees need declarative boundary directives (`:hydrate="visible"` or `:hydrate="idle"`) that keep SSR markup intact while deferring host attachment until actually required.

## Required Contract

1. **Template Directive**:
   - Syntax: `:hydrate="visible"` or `:hydrate="idle"`.
   - Compiles into `data-hydrate="visible"` or `data-hydrate="idle"` on container elements.
2. **Activation Strategies**:
   - **`visible`**: Subtree hydration is deferred until an `IntersectionObserver` detects the element entering the viewport (with a 100px lookahead margin).
   - **`idle`**: Subtree hydration is scheduled via `requestIdleCallback` (with a timeout fallback), executing when the browser main thread is quiescent.
3. **State Preservation**:
   - Pre-rendered static markup remains fully accessible and visually stable prior to hydration.
   - Once activated, event listeners, live regions, and patch subscribers seamlessly attach without DOM replacement or visual flicker.

## Acceptance Checklist

- [x] Specify neutral capability contract for streaming island hydration.
- [x] Add `:hydrate="visible|idle"` directive support to template compiler (`tools/template/compiler.zig`).
- [x] Implement lazy island activation coordinator in `web/dom.js`.
- [x] Verify viewport entry activation and idle deferred hydration across Chromium and Firefox.
