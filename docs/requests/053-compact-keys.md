# Request 053: stable compact keys for arbitrary external identifiers

Status: implemented and provider verified; consumer acceptance is separate.

## Reusable problem

Database records, remote services, and business models frequently identify entities using
arbitrary external identifiers, such as UUID strings (`"018f3a5e-b24a-..."`), text slugs
(`"billing-pro"`), 64-bit integer primary keys (`u64`), or sparse IDs (`10042891`).

Previously, `zg-gui` templates required `:key` to resolve directly to a dense, small `u32`.
Raw 64-bit identifiers, strings, or sparse integers cannot be used directly in keyed loops
because DOM node ID derivation relies on `(key + 1) * stride + slot` and Cantor pairing
in nested loops:
- Multiplying by large or sparse keys causes `u32` integer overflow.
- Strings cannot be multiplied by numerical strides.
- Deriving keys naively from array indices (`0..N`) breaks identity whenever lists are
  sorted, filtered, or prepended, causing form drafts and focus to be destroyed.

This request delivers zero-allocation, bounded `CompactKeyRegistry` abstractions that map
arbitrary external keys (value types, 64-bit integers, and strings) into stable, dense
compact `u32` keys in $[0, Capacity)$, with deterministic slot retention across frames.

## Delivered contract

1. **Compact Key Registry**:
   - `CompactKeyRegistry(comptime KeyType, comptime capacity: usize)` provides a fixed-capacity,
     zero-heap-allocation mapper from arbitrary values (such as `u64`, `i64`, `[16]u8`) to
     dense `u32` indices in $[0, capacity)$.
   - `StringCompactKeys(comptime max_key_len: usize, comptime capacity: usize)` provides
     inline-stored string key mapping for UUIDs and slugs without heap allocation or lifetime
     hazards.
   - `BorrowedStringCompactKeys(comptime capacity: usize)` provides compact key mapping for
     borrowed string slices (`[]const u8`).

2. **Stability & Slot Retention**:
   - `getOrAssign(key)` returns the existing dense slot if the key was already registered,
     or allocates the lowest available slot in $[0, capacity)$.
   - As long as an entity remains present, its compact index $k$ is invariant across
     permutations, sorting, and insertions of other items.
   - Reordering rows in a 100-item table generates surgical DOM `move` (`M`) commands
     instead of replacing elements or losing controlled input draft state.

3. **Lifecycle & Slot Recycling**:
   - `retain(active_keys: []const KeyType)` reconciles the registry against the current frame's
     items: slots for keys no longer in the active set are reclaimed and made available for
     new entities in subsequent frames.
   - `release(key)` explicitly de-registers an entity.
   - `clear()` resets all slot allocations.

4. **Safety & Overflow Bounds**:
   - Registering more distinct entities than `capacity` returns `error.CapacityExceeded`,
     invalidating candidate output before publication.
   - `binding.asKey(value)` in `src/template.zig` admits integer types (`u8`, `u16`, `u32`,
     `usize`, `u64`) within `u32` bounds, invalidating output on overflow (`error.InvalidKey`).

## Verification

- `src/compact_key.zig`: unit tests verify:
  - Stable slot retention across permutations and reorderings.
  - Slot recycling after `retain` drops absent items.
  - Collision-free assignment and capacity boundary enforcement (`error.CapacityExceeded`).
  - String keys with inline buffer storage and borrowed slice lookups.
  - 64-bit integer mappings.
- `tools/template/compiler.zig`: compiler tests verify:
  - Typed `:key` binding with `binding.asKey`.
  - Compile-time error when passing invalid key types.
- Verification in `tests/templates/generated_test.zig` ensuring reordered rows with
  compact keys emit `M` (move) commands without replacing DOM nodes.
