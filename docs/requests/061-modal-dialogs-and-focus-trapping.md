# Request 061: Modal Dialogs & Focus Trapping

Status: implemented; declarative dialog focus trapping (:trap-focus, :dialog), background inerting, keyboard cycling, and focus restoration upon dismissal.

## Reusable Problem

Modal dialogs and drawer overlays require strict keyboard focus management to meet accessibility standards (WCAG 2.1 SC 2.1.2 No Keyboard Trap and SC 2.4.3 Focus Order):
1. **Focus Leakage**: When pressing `Tab` or `Shift+Tab` within an active modal, focus often escapes into hidden or background application content.
2. **Missing Escape Dismissal**: Users expect `Escape` to dismiss active modal dialogs and return focus cleanly to the trigger button that opened them.
3. **Background Interaction**: Without modal inerting, background content remains clickable and focusable, creating confusion for screen-reader and keyboard users.
4. **Focus Restoration Loss**: When an overlay closes, focus often falls back to the top of the `<body>` element instead of the element that launched the modal.

This request introduces declarative focus containment and accessible dialog lifecycles into `zg-gui`.

## Required Contract

1. **Declarative Directive**:
   - Template elements can declare focus trapping statically or dynamically:
     ```html
     <div role="dialog" aria-modal="true" :trap-focus="$open">
       <header>
         <h2>Confirm Action</h2>
         <button type="button" aria-label="Close" :on-click="$close">×</button>
       </header>
       <p>Are you sure you want to proceed?</p>
       <button type="button" :on-click="$confirm">Confirm</button>
     </div>
     ```
   - Emits `data-trap-focus="true"` and `aria-modal="true"` when active.

2. **Keyboard Focus Cycling**:
   - `Tab` navigates sequentially through all focusable elements inside the active trap (`button`, `a[href]`, `input`, `select`, `textarea`, `[tabindex]:not([tabindex="-1"])`).
   - Tabbing forward from the last focusable element wraps to the first focusable element.
   - `Shift+Tab` from the first focusable element wraps to the last focusable element.

3. **Standard Escape Handling & Focus Restoration**:
   - Pressing `Escape` while focus is inside the trap triggers modal dismissal (via close button click or synthetic event) and restores focus to the trigger element that had focus before the modal was opened.

4. **Zero Runtime Heap Allocation**:
   - Evaluated as Booleans within existing snapshot slots in Zig models.

## Acceptance Checklist

- [x] Specify compiler grammar and code generation for `:trap-focus` and `:dialog` directives.
- [x] Implement focus trapping, Tab/Shift-Tab cycling, and Escape key dismissal in `web/dom.js`.
- [x] Implement focus restoration to preceding active element upon modal close.
- [x] Verify multi-engine browser compliance across Chromium and Firefox.
