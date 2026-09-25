# Request 052: typed multiple selection, change events and recovery

Status: implemented and provider verified; consumer acceptance is separate.

## Reusable problem

Forms and interactive workspaces frequently require selecting multiple items from a set,
such as choosing categories, assigning tags, or configuring multiple notification channels.
Previously, `<select multiple>` was rejected at compile time because multi-selection
could not be modeled through the single-value projection (`#value`) without ambiguous
change tracking, lost DOM focus, or improper SSR rendering.

This request delivers typed multiple selection for `<select multiple>`, option selection
membership, and checkbox group array bindings (`:values`) with deterministic diffing,
zero-allocation serialization, and DOM state recovery across patch stream cycles.

## Delivered contract

1. **Declarative Multiple Selection**:
   - `<select multiple>` admits the `:values` directive (e.g. `:values="$selected"`),
     where `$selected` binds to a slice or array of string identifiers or typed values.
   - Using `:value` on a `<select multiple>` fails compilation, requiring `:values`.
   - Using `:values` on a `<select>` without the `multiple` attribute fails compilation.
   - An explicit `:input` directive on `<select multiple>` binds change events to the
     view's input handler.

2. **Checkbox Groups & Option Membership**:
   - `<input type="checkbox" value="..." :values="$selected">` evaluates membership of
     its `value` in the bound `$selected` collection:
     - On SSR: emits `checked` when the value is present.
     - On WASM: tracks checked state in snapshots and emits `C\t<node>\ttrue/false`
       patches without re-rendering containing rows or unmounting DOM nodes.
   - `<option value="..." :values="$selected">` similarly derives `selected` attribute
     state based on membership in `$selected`.

3. **Wire Protocol & DOM Synchronization**:
   - The `<select multiple>` element emits `data-select-values="val1\x1fval2\x1f..."`
     serialized with standard ASCII Unit Separator (`\x1f`, `0x1F`).
   - Browser DOM host (`dom.js`) monitors `data-select-values` during full initialization,
     surgical attribute patches (`A`), option insertions (`J`), and removals (`D`):
     - Every `<option>` in the `<select>` has its `selected` DOM property updated to match
       membership in the declared set.
     - Focus, scroll position, and active element state are strictly preserved.
   - When users interact with `<select multiple>`, the `change` event produces an
     input value via `declaredInputValue`: selected options are joined by `\x1f`,
     dispatched via standard `setInput` without lossy stringification.

4. **Zero-Allocation Projection**:
   - `binding.selectedValues` formats the values into a bounded stack buffer and
     synchronizes `#values` and `data-select-values`.
   - Values containing illegal control characters (`\t`, `\r`, `\n`, `\x1f`) fail
     validation explicitly (`p.html.failed = true`), preventing malformed command stream
     publication.
   - `binding.iterateValues(payload)` provides a zero-allocation iterator over
     unit-separated multi-selection payloads.

## Verification

- `src/template.zig`: unit tests verify `containsValue`, `selectedValues` serialization,
  and delimiter rejection.
- `tools/template/compiler.zig`: compiler tests verify:
  - Admitting `<select multiple :values="$selected">`.
  - Rejecting `:value` on `<select multiple>` and `:values` on single `<select>`.
  - Admitting checkbox groups with `:values`.
- `tests/templates/multi_select.gui.html` & `tests/templates/generated_test.zig`:
  - Static clean HTML and hydrated HTML (`data-node-id`) rendering.
  - Adding and removing selections emits minimal `A` and `C` patch commands.
  - Checkbox groups synchronize checked state accurately with the array model.
