# Optional MathML integration

Core GUI builds acquire no typesetter dependency. A consumer selects the public
`math_typesetter` module and registers the adapter separately:

```zig
const gui_dep = b.dependency("zg_gui", .{ .target = target, .optimize = optimize });
const engine = b.dependency("math_typesetter", .{ .target = target, .optimize = optimize });
owner.addImport("zg_math", @import("zg_gui").addMath(b, .{
    .dependency = gui_dep,
    .typesetter = engine.module("math_typesetter"),
}));
```

The provider must expose `Options`, `Diagnostic`, and
`renderMathMlAlloc(allocator, source, options)` returning its owned
`RenderResult` (`output`/`diagnostic`, `deinit(allocator)`). The supported reference
provider is zig-math-typesetter 0.4.0. No private parser or normalized-tree imports
are needed. The consumer selects and pins its provider separately.

```zig
const math = @import("zg_math");
var formula = math.Formula.init(.{ .allocator = allocator, .output_limit = 8192 });
defer formula.deinit();
switch (try formula.update(.{ .source = "x_1 = \\frac{a}{b}" })) {
    .changed => {},
    .unchanged => {},
    .diagnostic => |failure| { _ = failure; },
}
// formula.output is borrowed serialized MathML; formula.revision starts at 1.
```

`Formula` owns copied `source` and accepted `output`. Treat its fields as read-only
views. Exact source/options equality returns `unchanged` without parsing or
allocation. A successful change invalidates old borrowed slices and increments
the checked revision. Source diagnostics, allocation failure, `OutputLimit`, and
`RevisionOverflow` preserve the previous accepted fields. `deinit` releases bytes
and resets to an empty reusable value. It is not a thread-safe shared cache.

The output limit controls accepted serialized bytes, not peak parser memory:
apply the provider's source/node/depth limits as well. One-shot rendering releases
its parsed document before returning; only accepted source/output remain cached.
No atomic transaction with the browser is promised. To combine formula ownership
with projection admission, prepare a separate candidate and swap it only after
the caller's HTML/patch output succeeds.

## Browser surface and lifecycle

Template text transport escapes the serialized payload:

```html
<div data-math-surface="" data-math-active="$active">
  <span hidden data-math-source="" :text="$mathml"></span>
  <span data-math-output=""></span>
</div>
```

Import `createMathHost` from `zg-gui/math-host` (or the installed public
`web/math-host.js`). Create it before mounting:

```js
const math = createMathHost({root, onError});
const app = await load({root, url: './app.wasm', onPatch: () => math.sync()});
// On teardown:
math.dispose();
app.dispose();
```

`onPatch(root)` is optional on `createDomHost`, `mount`, `load`, `createApp`, and
`mountWorker`. It runs synchronously after completed initialization, hydration,
and every successfully applied patch stream, including an empty stream. It runs
after ordinary declarations/focus/layout work. `onStructure` retains its existing
structural-scoping semantics. Callbacks must avoid reentrant projection changes.
Thrown callback failures follow the existing full-recovery/error behavior;
initialization failure is reported to the mounting caller.

The math host has `sync()`, `stats()` and idempotent `dispose()`. Synchronization
validates a detached tree before replacing only the declared output's children.
The output must be empty in GUI templates and exclusively owned by this adapter.
Source/output nodes are distinct direct children; the source must be hidden and
contain text only. Unchanged payloads preserve MathML node identity. Invalid
payloads call `onError(error, {surface})` and retain accepted output. Repeated
identical rejections are coalesced; oversized payloads use bounded diagnostic
fingerprints. The default reports to the console without throwing. Supply a
nonthrowing handler to keep rejection local. With no accepted formula, consumers
can display escaped source or their own diagnostic in a separate sibling.

Set `data-math-active="false"` to release a surface, or remove it and synchronize.
Removed/replaced owners are dropped on the next sync, including full resync.
`dispose()` removes owned generated nodes and all bookkeeping. The adapter itself
installs no listeners, observers or timers. Consumers invoke sync through their
projection hook and dispose it with their GUI owner.

Default limits are 65,536 UTF-8 bytes per payload, 4,096 tree nodes including text,
depth 64, and 64 tracked surfaces. Override with positive safe integers
`maxBytes`, `maxNodes`, `maxDepth`, `maxSurfaces`. `stats()` reports current surfaces,
accepted updates, rejections and disposal; counters are observations, not budgets.

## Finite output vocabulary

The host accepts MathML namespace `http://www.w3.org/1998/Math/MathML` exclusively.
Root: one `math`, with exactly `class="zig-math"`, `display="inline|block"`.
Descendants: `mrow mi mn mo mtext mspace mfrac msqrt mroot msub msup msubsup
munder mover munderover mstyle mtable mtr mtd`. Text nodes are allowed; comments,
nested math roots, HTML, unknown elements, URLs, IDs, styles and events are refused.

| Element | Fixed attribute values |
| --- | --- |
| mspace | width: -0.1667em, 0.1667em, 0.2222em, 0.2778em, 0.3333em, 1em, 2em |
| mtd | columnalign: right, left |
| mi | mathvariant: normal |
| mfrac | displaystyle: true, false; linethickness: 0 |
| mover | accent: true |
| munder | accentunder: true |
| mo | stretchy: true |
| mstyle | displaystyle/scriptlevel pairs: true/0, false/0, false/1, false/2 |
| mstyle | mathsize: 0.5em, 0.7em, 0.8em, 0.85em, 1em, 1.2em, 1.44em, 1.73em, 2.07em, 2.49em |
| mstyle | mathcolor: black, white, red, green, blue, cyan, magenta, yellow, gray, orange, purple, brown |

An `mstyle` has exactly one size/color attribute or one documented style pair.
Other descendants have only the documented attributes for their tag. This is a
finite provider-output admission boundary, not a general MathML/HTML sanitizer,
TeX implementation, math editor, font backend, or complete syntax validator.

`zig build test-math` checks ownership/failure with a synthetic public provider
and compiles freestanding WASM. It honors `-Doptimize=safe`. Browser checks use
`zig build test-browser -Dbrowser-filter='browser math'` and cover semantic trees,
identity, rejection, capacity limits, removal, recovery and teardown. Real-provider
and application acceptance remain the independent consumer's responsibility.
