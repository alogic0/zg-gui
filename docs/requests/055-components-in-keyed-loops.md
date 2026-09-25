# Request 055: component invocation inside keyed loops

Status: implemented and verified.

## Reusable problem

In complex workspaces and data-dense user interfaces, lists frequently render repeated,
interactive items such as editable task cards, user profile tiles, comment threads, or
faceted filter widgets. In [Request 001](001-template-components.md), reusable template
components (`<template:component>`) were introduced with typed inputs, isolated namespaces,
and compile-time snapshot sizing, but component invocation inside `:loop` elements was
explicitly left unsupported:

> "Nested components and component-owned keyed loops are supported. Invocation inside keyed loops remains explicitly rejected." (Request 001)

As a result, consumers building rich lists must either duplicate the component markup
inline within every loop row template, or construct manual nested projection layers in Zig.

This request lifts that remaining constraint by specifying declarative component invocation
inside keyed `:loop` elements, with deterministic collision-free node identities, derived
capacity scaling, and zero-allocation diffing.

## Required contract

1. **Declarative Invocation Inside Loops**:
   - Templates admit `<template:component_name>` inside the repeated row element of a `:loop`.
   - The component's `:view` directive binds to `$item` (or an item property/sub-model),
     e.g.:
     ```html
     <ul :loop="$tasks" :key="id" :limit="50">
       <li :key="$item.id">
         <template:task_card :view="$item" :ref="card" />
       </li>
     </ul>
     ```
   - Actions and event handlers declared inside the component route through the parent
     view's action dispatcher, passing the item context or key without manual wiring.

2. **Deterministic Keyed Node Identities**:
   - Each component node ID inside an item iteration must be globally unique, collision-free,
     and stable across list insertions, deletions, and reorderings.
   - Node identities are derived from a combination of the row key $K$, the component slot
     stride $S_{\text{comp}}$, and the local template node offset $O_{\text{node}}$:
     $$\text{id} = (K + 1) \cdot S_{\text{comp}} + O_{\text{node}}$$
   - Generated IDs must not collide with static template nodes, outer loop containers, or
     sibling components.

3. **Compile-Time Capacity & Storage Derivation**:
   - The combined snapshot capacity scales predictably by multiplying the loop's `:limit`
     by the component's individual snapshot requirement:
     $$C_{\text{loop\_comp}} = L_{\text{loop}} \times C_{\text{component}}$$
   - Exceeding declared limits or introducing duplicate keys rejects candidate updates
     cleanly before publication, preserving zero-heap-allocation invariants.

4. **Surgical DOM Patching & Identity Preservation**:
   - When a single item in the collection updates, only the affected component instance
     receives surgical DOM patches (`T`, `A`, `C`, etc.).
   - Reordering rows moves the component's root DOM node via standard keyed movement (`M`)
     without rebuilding, remounting, or losing input focus inside the component.

## Acceptance checklist

- [x] Specify template compiler grammar for `<template:name>` within `:loop` contexts.
- [x] Implement collision-free node ID stride calculation and qualified reference resolution.
- [x] Statically derive combined snapshot and buffer limits based on $L_{\text{loop}} \times C_{\text{comp}}$.
- [x] Support `$item` and child path bindings to component `:view` inputs with compile-time type validation.
- [x] Verify surgical patch generation on property changes without sibling or row replacement.
- [x] Verify retained input focus, cursor position, and DOM identity during row reordering.
- [x] Enforce limit bounds and reject duplicate keys, malformed views, and invalid references.
- [x] Validate both WASM surgical patch streams and static SSR HTML code generation.
