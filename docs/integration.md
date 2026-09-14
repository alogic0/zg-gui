# Integration and ownership

## Importing the package

Use the pinned compiler in `.zigversion`. Add a path dependency to your own
`build.zig.zon` (adjust the relative path):

```zig
.dependencies = .{
    .zg_gui = .{ .path = "../zg-gui" },
},
```

In your `build.zig`, where `app` is your compilation step:

```zig
const gui = b.dependency("zg_gui", .{ .target = target, .optimize = optimize });
app.root_module.addImport("zg_gui", gui.module("zg_gui"));
```

Copy/install the package's `web` directory next to your browser entrypoint and
WASM file, preserving the relative JavaScript imports. Use your own HTML and CSS.
No npm package is required at runtime; these are plain browser ES modules.

```js
import { load } from './runtime.js';
const app = await load({
  root: document.querySelector('#app'),
  url: './app.wasm',
  onError: error => console.error(error),
});
// Later, on application teardown:
app.dispose();
```

`load` accepts optional WebAssembly `imports`. `mount` accepts an already-created
instance's `exports` as `wasm`. Each instance belongs to one root; instantiate
separately for multiple applications. Mounting twice on one root is rejected.
Disposal removes listeners and rejects later actions; it leaves the final DOM
available to its owner. Drop instance/host references to release WASM memory.

## Application ABI

Export memory and these functions from a freestanding wasm32 module:

| Export | Result / meaning |
| --- | --- |
| `init() u32` | Reset and produce full HTML; return its byte length |
| `resync() u32` | Produce full HTML for current state after a failed patch |
| `dispatch(action: u32, value: i32) u32` | Apply an action, return patch byte length |
| `setInput(kind: u32, length: u32) u32` | Read admitted exchange bytes, return patch length |
| `getRenderBuffer() usize` | Pointer to the current output bytes |
| `getRenderLength() u32` | Current output byte count |
| `getRenderMode() u32` | `0` full HTML, `1` patch stream |
| `getExchangeBuffer() usize` | Pointer to writable exchange bytes |
| `getExchangeCapacity() u32` | Maximum accepted exchange byte count |

The ABI's positional scalars should immediately become named inputs inside Zig.
All subsequent state changes must produce patches. Full HTML is used only for
initialization and explicit recovery. Recovery can lose uncontrolled browser
drafts/focus; durable application state must be owned in Zig. The example's row
drafts are deliberately uncontrolled to demonstrate DOM retention, not persistence.

The host creates fresh typed-array views after each WASM call, allowing memory
growth. It rejects oversized UTF-8 input before dispatch; lengths are byte counts.
Zig must also validate lengths and UTF-8 before copying input. Buffers must remain
valid until the host synchronously reads their output. Never retain exchange
slices in state without copying them into state-owned storage.

## Projection lifecycle

Use `gui.Projection(capacity)` with a previous and next snapshot. Capacity counts
tracked node/property pairs, not nodes or HTML bytes. The caller owns snapshots,
HTML scratch and patch output; none allocate. Size fixed storage from measured
use, or allocate it in your owner when larger/optional. No framework singleton
or maximum application buffer is imposed.

1. Prepare a candidate state and an empty next snapshot.
2. Initial render uses `writing = true`, no previous snapshot and no patch writer.
3. Updates use `writing = false`, the last committed snapshot and a patch writer.
4. Call the same projection to record every relevant leaf and structural owner.
5. Check **both** the scratch HTML writer and the patch output writer's `failed`.
6. Only on success publish the candidate state, next snapshot and complete output.

`Writer.slice()` is a borrowed view and can contain a partial prefix on overflow.
It is not an admission check. Never publish it after `failed`, clip a saved value,
or commit a failed next snapshot. See `render` in `examples/demo.zig`.

Snapshots use the source implementation's 64-bit hashes and linear lookup of
previous entries. They are compact change detectors with theoretical hash
collisions and quadratic worst-case comparison cost, not exact-value storage.
Use scoped projections and explicit revision/membership keys; large-list
optimization and exact comparisons remain future work.

## Stable owners and declared events

Each patched `data-node-id` must resolve exactly once inside the root when its
command executes. Keep IDs stable across renders; disjoint `patch.Range`s help
allocate repeated row IDs. The root container itself is outside the ID namespace.

Use `text`, `attr`, `visible`, form-value and checked updates for leaf state.
Wrap a genuinely changing child list with `beginList` / `endList` and a membership
key. Newly introduced descendants are included in that owner's HTML, suppressing
separate commands to absent nodes. For retained rows, use `keyedList`,
`beginChild` / `endChild`, then `order`. Children must be direct siblings, IDs must
not repeat, and retained children must not change parent within a keyed list.

`data-event="N"` forwards a click action; optional `data-value` supplies an i32.
`data-input-kind="N"` forwards text input; checkbox/radio/select controls use
change events. Use `data-value-format="checked"` for Boolean checkbox values.
The host preserves modified link clicks and skips disabled/inert controls.
No debounce, routing, fetch effects, storage, modals or focus trap is implicit.
Use `dispatch({action, value})` and `setInput({kind, value})` for other adapters.

Application-owned markup, attribute names and membership keys are trusted.
Escape untrusted text with `escaped`/`text`; never interpolate it into raw HTML,
attribute names or tag names. The host's attribute allowlist is validation, not an
HTML sanitizer. Use an appropriate page CSP for your deployment. `onStructure`
is an optional synchronous host binding callback after introduced markup has
been installed, suitable for attaching a custom capability to declared nodes.
