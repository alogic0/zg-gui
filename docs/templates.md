# Compiled GUI templates

Templates are HTML fragments with a small binding language. SuperHTML tokenizes
the source; the GUI compiler validates its structure and generates ordinary Zig
projection functions. The tokenizer, compiler and template source run only at
build time. There is no template interpreter in the browser or WASM module.

The working demo is split into [markup](../examples/demo.gui.html) and
[state/view values](../examples/demo.zig). Both native tests and the WASM build
consume the same generated module. Editing the template and rebuilding is enough;
there is no separate generation command to remember for this example.

```html
<section>
  <input :value="$name" :input="$inputs.name">
  <p>Hello <span :text="$name"></span>.</p>
  <output :ref="counter" :text="$count"></output>
  <button :on-click="$actions.increment">Increment</button>
  <ul :loop="$rows" :key="id" :limit="20">
    <li><span :text="$item.label"></span></li>
  </ul>
</section>
```

## Bindings

Values such as `$name` and `$user.name` read fields from the supplied Zig view.
`$item.label` reads the current loop item. Bindings must be quoted and occupy
the whole attribute value. Arithmetic, method calls, indexing and string
interpolation belong in Zig; expose their results as view fields. A leading
literal dollar sign in a static attribute can be written as `&#36;`.

| Syntax | Type and generated behavior |
| --- | --- |
| `:text="$value"` | Escaped text leaf; string, integer, bool or enum |
| `title="$value"`, `aria-expanded="$open"`, `data-theme="$theme"` | Named attribute update; optional values remove the attribute |
| `disabled="$busy"` | Boolean attribute presence; requires bool or optional bool |
| `:value="$draft"` | String value property on input or textarea; textarea content must be empty |
| `:checked="$enabled"` | Boolean checked property on a static checkbox/radio input |
| `:visible="$open"` | Boolean visibility; retain the element and all descendants |
| `:if="$show"` | Retain the element as a structural owner; hide it and remove its children when false |
| `:on-click="$actions.save"` | Positive enum action ID forwarded to `dispatch` |
| `:input="$inputs.name"` | Positive enum input-kind ID forwarded to `setInput` |
| `:loop="$rows" :key="id" :limit="20"` | Reconcile direct keyed children, admitting at most 20 items |
| `:ref="counter"` | Export a static ID as `template.nodes.counter`, useful for focused tests |

`actions` and `inputs` are ordinary view fields containing enum values. No
particular enum or struct names are imposed. Checkbox/radio input directives
automatically declare the host's checked-value format. Form drafts must still
be copied into application-owned state when inputs arrive.

Text bindings require empty, non-void elements. A loop directive belongs on
the container, which must have exactly one child element as the row template.
Each item key must be a stable `u32`. The compiler derives every repeated
descendant's ID from its template slot and item key, so edits and reordering
retain controls, focus, and browser-owned state. Duplicate keys, excessive
item counts and ID arithmetic overflow set the HTML writer's failure flag.
Never publish either output or the candidate snapshot when a writer failed.

Numeric keys are not arbitrary database IDs: very large keys can exceed the
32-bit DOM namespace. The formula is `(key + 1) * element_count + slot`.
Use stable compact application keys when external IDs do not fit. Different
loops have disjoint template slots, so equal keys across those loops are valid.
One generated tree owns one root namespace; independently generated templates
cannot yet be composed under the same root without an explicit namespace layer.

The generated module exposes `project(p, view)`, `nodes`, and
`snapshot_capacity`. Use `gui.Projection(template.snapshot_capacity)` and the
normal previous/next snapshot lifecycle. The capacity counts all potentially
tracked properties, including each loop's declared admission limit; choose
limits appropriate to the application and its memory budget. Static HTML is
emitted only while a projection is writing an introduced subtree.

## Building

For a direct invocation:

```sh
zig build
zig-out/bin/zg-template path/to/view.gui.html path/to/generated.zig
```

The command reports malformed templates as `file:line:column: message` and does
not open the output until validation succeeds. Missing view fields produce Zig
compile errors naming the template location; Zig also checks property and event
types when the generated projection is instantiated.

In a consuming project's build, use the package's native compiler artifact:

```zig
const dependency = b.dependency("zg_gui", .{ .target = target, .optimize = optimize });
const gui = dependency.module("zg_gui");
const generate = b.addRunArtifact(dependency.artifact("zg-template"));
generate.addFileArg(b.path("view.gui.html"));
const generated = generate.addOutputFileArg("view.zig");
app.root_module.addImport("zg_gui", gui);
app.root_module.addImport("view", b.createModule(.{
    .root_source_file = generated,
    .target = target,
    .optimize = optimize,
    .imports = &.{.{ .name = "zg_gui", .module = gui }},
}));
```

This makes template edits build dependencies and keeps generated code in Zig's
cache. Generated code should not be hand-edited or checked in.

## Current language boundary

This is a GUI-specific subset, not the complete SuperHTML/Scripty language.
There is no raw HTML injection, `:else`, nested loop, component invocation,
runtime expression evaluation, or implicit persistence. `:if` owns children;
use `:visible` when hidden descendants must retain drafts and focus identity.
Refs inside loops are rejected because their IDs depend on the current key.

Supported lowercase tags are: main, header, footer, section, article, aside,
nav, div, p, span, h1–h6, a, strong, em, small, b, i, code, pre, br, hr, form,
fieldset, legend, label, input, textarea, button, output, ul, ol, li, img,
details and summary. Closing tags must match explicitly; non-void self-closing
tags are rejected. Tables, select/options, SVG, scripts, styles and full document
markup need dedicated semantics and are rejected by this first compiler.

Dynamic attributes are restricted to class, lang, disabled, readonly, autofocus,
inert, role, title, placeholder, alt, and supported aria/data names. Internal
node/event/input IDs and dynamic host formatting directives are reserved.
Inline event-handler attributes are rejected; page styling belongs in CSS.
Literal text, comments, whitespace, entities and quoted static attributes are
preserved. Applications must not put untrusted values in raw template source.

Admission bounds: 256 KiB UTF-8 source, 4096 elements, depth 64, 64 attributes
per element, and loop limits from 1 to 1024. These are compile-time validation
limits, not a reservation of source-parser storage in the application.

Run `npm run test:templates` for parser/compiler checks, generated projection
tests, allocation-failure coverage, and expected compiler diagnostics. Vendored
files and their unchanged source hashes are recorded in `vendor/superhtml/`.
`npm test` additionally creates a temporary independent Zig package and verifies
the public compiler-artifact integration shown above.
