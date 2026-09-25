# Request 056: CSS transitions and exit lifecycle hooks

Status: proposed roadmap capability; specification and contract defined.

## Reusable problem

In interactive graphical applications, elements entering or leaving the viewport frequently
require animation (e.g. fading out a dismissed notification, collapsing a deleted task row,
or sliding out a drawer).

Currently, when an item is removed from a collection (emitting a delete command `D`) or
conditionally hidden via `:visible`, the DOM host (`dom.js`) immediately detaches the element
from the DOM tree. If an exit transition is attempted purely in client CSS or userland
JavaScript, severe coordination failures occur:
1. **Node ID Recycling Race**: The Zig WASM engine may immediately recycle the deleted node's
   ID for a newly added element in the same or subsequent patch cycle while the old element
   is still animating in the DOM.
2. **Ghost DOM Collisions**: Re-inserting an item while an exit animation is still in progress
   leads to duplicate DOM elements with conflicting node references.
3. **Abrupt Visual Cuts**: Without framework-level coordination, elements pop out of existence
   instantaneously, preventing fluid visual polish.

This request delivers declarative CSS transition and exit lifecycle hooks that coordinate
DOM element detachment with CSS transition lifecycles before recycling node IDs.

## Required contract

1. **Declarative Transition Directives**:
   - Templates admit transition annotations on elements or loop items:
     ```html
     <li :key="$item.id" :exit-transition="fade-collapse">
       <span :text="$item.title"></span>
     </li>
     ```
   - Alternatively, configurable transition timing:
     `:exit-transition="{ name: 'fade-out', timeout: 300 }"`

2. **Coordinated Exit Lifecycle States**:
   - **Active**: Normal mounted and rendered state.
   - **Exiting**: Upon receiving a removal command (`D`) for a transitioning node:
     - The DOM host leaves the element attached in the DOM tree.
     - The DOM host applies CSS classes (`zg-exit`, `zg-exit-active`) to trigger CSS animations.
     - The element is marked inert (`pointer-events: none`, `aria-hidden: "true"`) to prevent
       spurious user interactions during exit.
   - **Detached**: When `transitionend` or `animationend` fires (or when the safety timeout
     elapses), the DOM host performs physical element removal (`remove()`) and signals node
     retirement to the registry.

3. **Node ID Retirement & Recycling Safety**:
   - While a node is in the **Exiting** state, its node ID remains reserved in the host node
     registry and cannot be reallocated or targeted by unrelated DOM mutations.
   - If the same keyed entity is re-added before the exit transition finishes (interrupted
     deletion / undo):
     - The exit transition is aborted.
     - The exit classes are removed, and enter classes (`zg-enter`, `zg-enter-active`) are applied.
     - The existing DOM node is re-adopted seamlessly without re-creation.

4. **Safety Timeouts & Degradation**:
   - If CSS fails to define a transition or `transitionend` does not fire (e.g. `display: none`
     or missing stylesheet), an automatic safety timeout (e.g. 500ms default) forces immediate
     detachment to prevent node ID leaks.
   - When the user agent prefers reduced motion (`prefers-reduced-motion: reduce`) or in headless
     test environments, transitions can be bypassed cleanly.

## Acceptance checklist

- [ ] Specify declarative `:exit-transition` syntax and compiler validation.
- [ ] Implement DOM host transition coordination in `dom.js` with `transitionend` and safety timers.
- [ ] Implement node ID hold/reservation in the node registry until exit completion.
- [ ] Handle transition cancellation (re-insertion of exiting keyed items) without DOM recreation.
- [ ] Verify zero runtime heap allocation in Zig WASM engine during exit phases.
- [ ] Verify browser interaction scenarios: smooth exit, rapid re-insertion, timeout fallback,
      and focus preservation on remaining siblings.
- [ ] Verify multi-engine browser compatibility (Chromium, Firefox Gecko, WebKit).
