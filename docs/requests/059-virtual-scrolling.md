# Request 059: Virtual scrolling and windowed projections

Status: implemented and verified.

## Reusable problem

In data-intensive applications—such as large CRM lead tables (10,000+ contacts), call log histories,
and high-frequency analytical feeds—maintaining full DOM trees for every collection item creates severe
browser bottlenecks:
1. **DOM Node Bloat**: 10,000 rows with 6 cells each results in 60,000+ DOM nodes, consuming tens of megabytes
   of browser C++ heap and causing noticeable scroll stuttering (jank).
2. **Snapshot Memory Pressure**: Snapshot diffing arrays in WASM scale linearly with total collection size
   unless windowed.
3. **Mobile Browser Limitations**: Low-memory mobile devices frequently crash or drop frames when DOM trees
   exceed several thousand elements.

While Request 053 delivered compact keys and Request 054 benchmarked large-list snapshots up to 1,000 items,
scaling beyond 1,000 items requires **Virtual Scrolling**: windowing the rendered output to only the visible
viewport slice plus a bounded overscan margin, while keeping scrollbars and native keyboard navigation authentic.

## Required contract

1. **Declarative Window Directives**:
   - Loops admit a declarative `:window` directive:
     ```html
     <tbody :loop="$items" :key="key" :window="{ itemHeight: 40, overscan: 5, total: $totalCount }">
       <tr>
         <td :text="$item.name"></td>
         <td :text="$item.status"></td>
       </tr>
     </tbody>
     ```
   - Emits `data-window-item-height="40"` and `data-window-overscan="5"`.

2. **Accurate Scroll Dimensions & Spacers**:
   - The DOM host or template SSR output maintains top and bottom spacers (or spacer rows):
     `height = startIndex * itemHeight` (top spacer) and `height = (total - endIndex) * itemHeight` (bottom spacer).
   - The native container scrollbar reflects the total dataset height ($N \times \text{itemHeight}$) accurately,
     supporting smooth native trackpad, wheel, and scrollbar drag interactions.

3. **Zero Heap Allocation Viewport Slicing**:
   - The Zig engine projects only the bounded active slice $[i_{\text{start}}, i_{\text{end}})$.
   - Snapshot capacity scales with the viewport window size $W \approx (\text{viewportHeight} / \text{itemHeight}) + 2 \times \text{overscan}$,
     completely decoupled from total item count $N$ (e.g. 35 entries regardless of whether $N = 100$ or $N = 100,000$).

4. **DOM Host Scroll Coordination**:
   - `web/dom.js` attaches a passive scroll listener to the nearest scrollable ancestor (`overflow-y: auto | scroll` or `window`).
   - Slices are debounced via `requestAnimationFrame` to maintain 60–120 FPS fluid scrolling.
   - When the window shifts, existing DOM rows are surgically updated via standard patch commands (`T`, `A`)
     and re-keyed moves (`M`), preserving focus and avoiding DOM thrashing.

## Acceptance checklist

- [x] Specify compiler grammar and validation for `:window` directive on `:loop` elements.
- [x] Implement spacer height calculation and viewport slice indexing in template compiler / SSR.
- [x] Implement passive scroll coordination and window bounds tracking in `web/dom.js`.
- [x] Verify constant $O(W)$ snapshot capacity and zero heap allocation in Zig WASM engine for 10,000+ item collections.
- [x] Verify authentic native scrollbar behavior and smooth trackpad scrolling.
- [x] Verify focus preservation when navigating within the windowed viewport.
- [x] Add browser tests exercising virtual scrolling and rapid scroll sweeps (Chromium & Firefox).
- [x] Ensure 100% test pass across `zg-gui`.
