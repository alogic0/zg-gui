# Request 067: Zero-Allocation FLIP Layout Transitions (:layout-id)

Status: implemented; declarative `:layout-id` directive with FLIP (First, Last, Invert, Play) transition coordinator and zero runtime heap allocation.

## Reusable Problem

In dynamic lists, grids, and tab navigation (e.g. reordering custom questions, sorting tables, moving cards between kanban columns), elements abruptly jump between positions when the DOM is patched. Standard CSS transitions do not animate changes in element flow or parent ordering:
1. **Layout Discontinuity**: When elements are moved or reordered via patch operations (`M` move or `R` replace), visual abruptness disrupts spatial comprehension.
2. **Allocation & Performance Overhead**: Traditional animation libraries allocate objects on every frame, create garbage collection pressure, and block the main thread.
3. **Declarative Identity**: Templates need a clean, declarative directive (`:layout-id="key"`) that coordinates layout transitions across patch cycles without modifying business models.

## Required Contract

1. **Template Directive**:
   - Syntax: `:layout-id="expression"` or `:layout-id="$item.id"`.
   - Compiles into `data-layout-id="key"` on the target element.
2. **FLIP Coordination Cycle**:
   - **First**: Before applying DOM mutations or move patches, the DOM host caches the initial bounding rectangles (`getBoundingClientRect()`) for all active `[data-layout-id]` elements.
   - **Last**: After applying patches and updating the DOM tree, the DOM host measures the new bounding rectangles.
   - **Invert**: For any element whose position has changed ($\Delta x \ne 0$ or $\Delta y \ne 0$), apply `transform = translate(dx px, dy px)` and `transition = 'none'`.
   - **Play**: In the next animation frame (`requestAnimationFrame`), restore `transform = ''` and enable `transition = 'transform 200ms cubic-bezier(0.2, 0, 0, 1)'`.
3. **Zero Runtime Heap Allocation**:
   - Bounding rects and coordinates are tracked using pre-allocated maps/WeakMaps without dynamic allocations during animation ticks.
4. **Graceful Degeneracy**:
   - Respects `prefers-reduced-motion: reduce`; skips animations when motion is disabled.

## Acceptance Checklist

- [x] Specify neutral capability contract for declarative FLIP layout transitions.
- [x] Add `:layout-id` directive support to template compiler (`tools/template/compiler.zig`).
- [x] Implement FLIP animation coordinator in `web/dom.js`.
- [x] Verify smooth reordering transitions and reduced-motion handling across Chromium and Firefox.
