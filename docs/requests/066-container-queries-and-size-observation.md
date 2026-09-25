# Request 066: Zero-Allocation Container Queries & Size Observation

Status: implemented; declarative `:observe-size` and container breakpoint reflection coordinating `ResizeObserver` events into DOM attributes and Zig event pipelines without heap allocation.

## Reusable Problem

Modern responsive component design requires components to adapt to their immediate container's dimensions rather than the global viewport (`@media (min-width: ...)`):
1. **Viewport vs Container Mismatch**: An element in a narrow sidebar or modal may have a small container even on a 4K desktop display.
2. **Polling Overhead**: Using polling timers or window `resize` listeners to measure element bounding boxes is inefficient, causes layout thrashing, and drains battery life.
3. **Memory Allocations**: Tracking resize metrics dynamically in WASM runtimes frequently leads to unbounded string or integer allocations.

## Required Contract

1. **Declarative Directive**:
   - Template elements can declare container observation:
     ```html
     <div :observe-size="compact:400,expanded:800">
       ...
     </div>
     ```
   - Emits `data-observe-size="compact:400,expanded:800"`.
2. **Automatic DOM Class / Attribute Reflection**:
   - `web/dom.js` attaches a shared `ResizeObserver` instance to observed elements.
   - When container width is under 400px: sets `data-size="compact"`.
   - When between 400px and 800px: sets `data-size="standard"`.
   - When 800px or greater: sets `data-size="expanded"`.
   - CSS can immediately target `[data-size="compact"]` without CSS container query polyfills.
3. **Optional Action Dispatch**:
   - If `:on-resize="$action"` is declared on the element, fires the associated action ID with the categorical size enum index when crossing breakpoint thresholds.
4. **Zero Runtime Heap Allocation**:
   - Breakpoint categories map to compact integer constants in Zig models.

## Acceptance Checklist

- [x] Specify compiler grammar and code generation for `:observe-size` directive.
- [x] Implement shared `ResizeObserver` lifecycle management in `web/dom.js`.
- [x] Verify threshold attribute reflection (`data-size="compact|standard|expanded"`).
- [x] Verify multi-engine browser compliance across Chromium and Firefox.
