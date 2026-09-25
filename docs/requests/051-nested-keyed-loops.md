# Request 051: nested keyed loops with explicit ownership and admission limits

Status: implemented and provider verified; consumer acceptance is separate.

## Reusable problem

Hierarchical view models frequently require grouped or nested lists, such as categories
with items, departments with members, and grouped tables. Previously, template loops
were restricted to a single level because nested child rows required deterministic,
collision-free node identities across dynamic outer and inner iterations without
hidden allocations or uncontrolled capacity growth.

This request delivers nested keyed loops with explicit ownership, Cantor-derived
collision-free node identities, and exact compile-time capacity derivation.

## Delivered contract

1. **Declarative Nesting**:
   - Templates admit a child container with `:loop`, `:key`, and `:limit` inside the
     row template of an outer `:loop`.
   - Nesting is verified up to depth 2; deeper nesting fails explicitly at compile time.
   - Each loop container enforces whitespace-only boundaries around its single repeated
     element.

2. **Hierarchical Scope & Bindings**:
   - Inside an inner loop, `$item` binds to the inner row item.
   - `$outer` (and `$outer.field`) binds to the enclosing outer row item.
   - Root view bindings (e.g. `$theme`, `$actions.select`) remain accessible at all depths.
   - Referencing `$outer` outside a nested loop fails compile-time validation.

3. **Collision-Free Identity Derivation**:
   - `binding.nestedKeyedId(.{ .outer_key, .inner_key, .slot, .stride })` computes:
     $$\pi(K_o, K_i) = \frac{(K_o + K_i)(K_o + K_i + 1)}{2} + K_i$$
     $$\text{id} = (\pi(K_o, K_i) + 1) \cdot \text{stride} + \text{slot}$$
   - By Cantor pairing bijectivity and slot modularity, derived node IDs never collide
     between distinct $(K_o, K_i)$ pairs, across different template slots, or with
     static template nodes.
   - Keys exceeding admission bounds ($K_o + K_i \ge 65536$) or invalid slots fail
     explicitly with `error.InvalidKey`, invalidating candidate output before publication.

4. **Bounded Capacity Derivation**:
   - Snapshot capacity accounts for nested limits:
     outer entries scale by $L_{\text{outer}}$, while inner entries scale by
     $L_{\text{outer}} \times L_{\text{inner}}$.
   - Exceeding declared limits or introducing duplicate keys rejects output at runtime.

5. **Dual-Target Projections**:
   - WASM Projections: inner lists maintain explicit `#parent` and `#order` relationships
     under their owning outer element node ID. Modifying, reordering, adding, or deleting
     inner items issues surgical DOM patch commands (`M`, `J`, `D`, `T`, `A`) without
     replacing the outer row or siblings.
   - SSR Static Rendering: `renderHtml` and `renderHtmlWithNodes` stream nested
     structures directly into caller-owned HTML buffers with zero heap allocations.

## Verification

- `src/template.zig`: unit tests verify `nestedKeyedId` non-collision across key/slot
  matrices, slot boundary checks, and overflow admission limits.
- `tools/template/compiler.zig`: compiler tests verify 2-level loop code generation,
  `$outer` scoping diagnostics, rejection of depth > 2, and exact capacity derivation.
- `tests/templates/nested_loop.gui.html` & `tests/templates/generated_test.zig`:
  - Static clean HTML and hydrated HTML (`data-node-id`) rendering.
  - Incremental WASM patch generation on inner item reordering (moves without replaces).
  - Swapping outer categories retains inner child identities.
  - Modifying outer context updates inner `$outer` text leaves.
  - Inner limit overflow and duplicate keys trigger explicit failure.
