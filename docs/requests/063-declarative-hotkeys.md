# Request 063: Declarative Hotkeys and Roving Tabindex

Status: implemented; declarative hotkey shortcuts (:hotkey) and roving tabindex (:roving-tabindex) keyboard accessibility navigation for toolbars, menus, and tabs.

## Reusable Problem

Power users and accessibility users rely on keyboard navigation:
1. **Global Keyboard Shortcuts**: Triggering actions like search (`Ctrl+K` / `Cmd+K`), save, or quick navigation currently requires ad-hoc window event listeners scattered across components.
2. **Composite Widget Navigation**: In toolbars, tablists, and menus, standard accessibility (WAI-ARIA Authoring Practices) requires arrow-key roving tabindex navigation instead of tabbing through every individual item.
3. **Shortcuts Colliding with Form Input**: Unfiltered key listeners accidentally trigger shortcuts while the user is typing into text fields or textareas.

This request introduces declarative global hotkeys and roving tabindex primitives into `zg-gui`.

## Required Contract

1. **Declarative Hotkeys (`:hotkey="combo"`)**:
   - Buttons, links, or interactive elements declare their activation key combo:
     ```html
     <button type="button" :hotkey="ctrl+k" :on-click="$open_search">Search (Ctrl+K)</button>
     <button type="button" :hotkey="alt+n" :on-click="$new_item">New item</button>
     ```
   - Emits `data-hotkey="ctrl+k"`.
   - The DOM host intercepts matching key combinations globally and invokes `.click()` on the matching visible element, unless typing in a text field (unless modifier or Escape is pressed).

2. **Roving Tabindex Navigation (`:roving-tabindex="horizontal|vertical"`)**:
   - Containers declare keyboard roving navigation:
     ```html
     <nav role="tablist" :roving-tabindex="horizontal">
       <button role="tab" tabindex="0">Day</button>
       <button role="tab" tabindex="-1">Week</button>
       <button role="tab" tabindex="-1">Month</button>
     </nav>
     ```
   - Arrow keys (`ArrowRight`/`ArrowLeft` or `ArrowDown`/`ArrowUp`), `Home`, and `End` move focus between sibling items, dynamically swapping `tabindex="0"` onto the focused item and `tabindex="-1"` onto the rest.

3. **Zero Heap Allocation**:
   - Evaluated as static attributes and standard DOM focus events.

## Acceptance Checklist

- [x] Specify compiler grammar and validation for `:hotkey` and `:roving-tabindex` directives.
- [x] Implement global keydown event dispatcher for `:hotkey` shortcuts in `web/dom.js`.
- [x] Implement arrow key roving tabindex navigation with boundary wrapping and Home/End support in `web/dom.js`.
- [x] Verify multi-engine browser compliance across Chromium and Firefox.
