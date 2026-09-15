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
| `:value="$draft"` | String value property on input, textarea or single select; textarea content must be empty |
| `:checked="$enabled"` | Boolean checked property on a static checkbox/radio input |
| `:visible="$open"` | Boolean visibility; retain the element and all descendants |
| `:if="$show"` | Retain the element as a structural owner; hide it and remove its children when false |
| `:on-click="$actions.save"` | Positive enum action ID forwarded to `dispatch` |
| `:input="$inputs.name"` | Positive enum input-kind ID forwarded to `setInput` |
| `:loop="$rows" :key="id" :limit="20"` | Reconcile direct keyed children, admitting at most 20 items |
| `:ref="counter"` | Export a static ID as `template.nodes.counter`, useful for focused tests |

`actions` and `inputs` are ordinary view fields containing enum values. No
particular enum or struct names are imposed. Checkbox/radio input directives
automatically declare the host's checked-value format by default. A static radio
can opt into its selected choice value with `data-value-format="value"`; use
one input kind for the group and distinct `value` attributes. Keep selection in
consumer state through `:checked`. Checkbox overrides, other radio formats and
dynamic formatting modes remain rejected. Form drafts must still
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
Independent templates can share a root using explicit disjoint namespaces; see
the composition guide below. The default namespace is for a standalone tree.

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

In a consuming project's build, register a template with the public build helper:

```zig
const dependency = b.dependency("zg_gui", .{ .target = target, .optimize = optimize });
@import("zg_gui").addTemplate(b, .{
    .dependency = dependency,
    .owner = app.root_module,
    .name = "view",
    .source = b.path("view.gui.html"),
});
```

Use a dependency configured for the owner's target and optimization mode. For
native tests and WASM builds, create one dependency per configuration and register
the template on each root module. The compiler itself always runs on the build
host. Applications using GUI runtime types directly can import the same
`dependency.module("zg_gui")`; the generated module shares that module instance.
Adapters to another projection API need only the generated `view` import.

The compiler artifact `dependency.artifact("zg-template")` and `generateTemplate`
build helper remain available for custom generation pipelines.

This makes template edits build dependencies and keeps generated code in Zig's
cache. Generated code should not be hand-edited or checked in.

## Current language boundary

This is a GUI-specific subset, not the complete SuperHTML/Scripty language.
There is no raw HTML injection, `:else`, nested keyed loop, runtime expression
evaluation, or implicit persistence. `:if` owns children;
use `:visible` when hidden descendants must retain drafts and focus identity.
Refs inside loops are rejected because their IDs depend on the current key.

Description lists support `dl`, `dt`, and `dd`, including direct div groups.
Terms/descriptions must be direct children of the list or its div group. Groups
contain only terms/descriptions; the list admits only these elements and whitespace
between children. Text bindings on `dd` update only that description.

Supported HTML tags include the original fragment elements plus `table`, `caption`,
`colgroup`, `col`, `thead`, `tbody`, `tfoot`, `tr`, `th`, `td`, `select`, `optgroup`
and `option`. Semantic `time` is supported in flow/phrasing content and table
cells, with escaped text and optional `datetime` bindings. Consumers supply and
validate dates and own timezone formatting; literal host formatting attributes
are preserved. Tables require explicit sections: put rows inside `tbody`, `thead`
or `tfoot`. Invalid table/select nesting and non-whitespace text between their
structural children are rejected before the browser can repair the tree.
Multiple-select controls require a separate value model and remain unsupported.

SVG supports `svg`, `g`, `defs`, `symbol`, `path`, `circle`, `ellipse`, `rect`,
`line`, `polyline`, `polygon`, `use` and `title`. SVG-only children require an SVG
container; HTML inside SVG and `foreignObject` are rejected. Self-closing SVG
shapes are accepted. HTML non-void tags still require explicit closing tags.
Static `viewBox` and `preserveAspectRatio` preserve their required case.
Dynamic SVG geometry and paint attributes are admitted explicitly; `use href`
accepts local sprite references such as `icons.svg#copy`, `/icons.svg#copy`, or
`#copy`, rejecting URL protocols and protocol-relative references before emission.

A controlled select's `:value` declares its value through `data-select-value` and
ordinary value patches. The host restores that declared value after option-list
changes, including initial render and recovery. If no option matches, the control
has no selection; reinserting a matching option restores it without changing Zig
state. The attribute is reserved for generated code. Options can bind `value` and
`:text`; keyed option lists keep retained options in place. `:input` on select
forwards change events. Update Zig state from the supplied value as for text input.
Dynamic option and selected values must be single-line: tab, CR and LF reject
the projection rather than being normalized by the attribute patch protocol.

Dynamic HTML attributes include class, lang, disabled, readonly, autofocus,
inert, role, title, placeholder, alt, id, for, datetime, draggable, and supported aria/data names.
Bind id/for from the composing view to keep label associations unique. Internal
node/event/input IDs and dynamic host formatting directives are reserved.
For `draggable`, supply enumerated strings (`true`, `false`, `auto`) or an
optional null to remove the attribute; `false` is not absence. Drag policy and
ordering remain consumer responsibilities. See [request 009](requests/009-draggable-attributes.md).
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

## Composing independently compiled panels

A generated module supports `Scoped(.{ .first = 1000, .count = 10000 })`.
Its `project`, `nodes` and `snapshot_capacity` use that reserved DOM ID range.
The original module-level API remains the default namespace starting at 1.
Use explicit, disjoint ranges when multiple templates or handwritten projections
share a root; call `gui.template.validateNamespaces(&.{ ... })` at comptime to
check the application's complete range assignment. Ranges reserve IDs, not memory.
Every static and keyed descendant must fit its range or the writer fails; never
publish a failed projection. Key limits still apply within each range.

Instantiate one template with different ranges to reuse a panel. Call the scoped
projections from a Zig composition owner, either using separate snapshots or a
combined projection sized to the sum of their capacities. This supports incremental
adoption alongside handwritten renderers through one DOM patch pipeline. Literal
HTML `id` attributes are not rewritten: use application-supplied associations when
reusing markup with labels. For invocation from markup, use components below.


## Reusable template components

Register named source files with `addTemplate` (or `generateTemplate`):

```zig
@import("zg_gui").addTemplate(b, .{
    .dependency = dependency,
    .owner = app.root_module,
    .name = "view",
    .source = b.path("view.gui.html"),
    .components = &.{
        .{ .name = "field", .source = b.path("field.gui.html") },
    },
});
```

Invoke the component using an empty, explicitly closed template element:

```html
<section>
  <template :component="field" :view="$first" :ref="first"></template>
  <template :component="field" :view="$second" :ref="second"></template>
</section>
```

For example, `field.gui.html` can contain:

```html
<label><span :text="$label"></span><input :ref="input" :value="$value"></label>
```

Pass typed values from Zig:

```zig
const Field = struct { label: []const u8, value: []const u8 };
view.project(&projection, .{
    .first = Field{ .label = "First", .value = "one" },
    .second = Field{ .label = "Second", .value = "two" },
});
```

Each `:view` is an explicit struct or single-item struct pointer. Bindings read
only that view's fields; missing fields and incorrect property/action types fail
Zig compilation. Even a static component requires a valid view. This is the same
structural typing as ordinary template views; the framework does not impose a
particular application struct or event enum.

`:ref` names the instance. Component-local refs become qualified names such as
`view.nodes.@"first.input"` and `view.nodes.@"second.input"`. Nested invocation
adds another segment, for example `view.nodes.@"first.editor.input"`. Instance
and local ref names must be simple identifiers; dots are compiler-owned. Repeated
instance names in the same scope are rejected, including components without refs.

Expansion emits the component's actual markup, with no `template` DOM element or
additional wrapper. All expanded elements share the parent's generated slot
allocation and `Scoped` range, so repeated instances have disjoint node IDs.
IDs remain stable through state updates, visibility changes and keyed reorder;
editing template structure can change numeric IDs. Use semantic refs and do not
persist generated IDs as application data. HTML `id`/`for` values remain consumer
owned: bind unique associations when reusing a component with explicit IDs.

The parent `snapshot_capacity` derives all expanded bindings and declared loop
limits. It includes each instance once; consumers must not add the component's
capacity again. Compose the resulting template with handwritten entries using
the normal snapshot lifecycle. Failure flags still require discarding candidate
HTML, patches and snapshots before publishing anything.

Components may invoke other registered components and contain their own keyed
loops. Invocation inside a keyed loop is rejected in this version. Components
inside `:if` follow its structural owner's lifecycle; `:visible` retains them.
Each source must be balanced independently, and the expanded tree undergoes the
normal HTML/SVG/table/select structure validation across component boundaries.
Recursive invocation, unknown sources, extra invocation attributes and nonempty
invocation content are rejected. Whitespace between invocation tags is allowed.

Bounds: 64 registered sources, 16 invocation levels, 256 expanded instances,
256 KiB per source and expanded document, and the existing 4096-element/depth-64
bounds on the final tree. These constrain build-time work, not runtime allocation.
Source files are explicit build dependencies: editing a nested component rebuilds
the generated consumer. No runtime compiler, source loader or second DOM host is
introduced. Diagnostics retain original source filenames, lines and columns.

The equivalent direct compiler command supplies name/path pairs after the output:

```sh
zig-out/bin/zg-template view.gui.html generated.zig field field.gui.html
```

See [panels.gui.html](../examples/panels.gui.html) for two instances of a component
containing keyed tables, SVG and a controlled select. Each instance receives its
own selection state; browser tests check that edits retain the other instance's
focused input and draft.

## Typed child slots and runtime fragment placement

Use a slot when the composing application owns child projection and membership:

```html
<section :ref="body" :slot="$children"></section>
```

`children` is a struct or single-item struct pointer with a public
`project(self, p, owner)` method. `owner` has the named `node: u32` field. The
compiler emits the slot element and invokes that method inside it on every
projection pass. The callback receives the same typed projection or adapter as
its parent. Use its ordinary text, attribute, visibility and structural methods;
there is no raw-HTML binding or runtime template loader.

Slots require an empty `div`, `section`, `dd`, `ul`, `ol`, `thead`, `tbody`, `tfoot` or single `select`, may retain their subtree through
`:visible`, and cannot also own text, a condition or a loop. Slots inside loops
or conditional subtrees are currently rejected. A select slot may also use
`:value`; its callback owns valid option/optgroup children, while the existing
controlled-value binding owns selection. Without `:value`, selection belongs to
the callback or host. Multiple selection remains unsupported. Consumer callbacks are responsible
for valid child markup, disjoint descendant IDs, structural introduction/removal,
failure propagation, and the smallest changed owner. The compiler cannot validate
the callback's emitted children or discover its memory costs.

The generated `snapshot_capacity` **excludes slot children**. The consumer must
add their declared costs when they share the parent's snapshot, or explicitly own
a separate snapshot/revision scheme. A slot does not reserve storage for a
maximum collection. Any writer failure invalidates the entire candidate output
and snapshot, including child work.

A separately compiled fragment also exposes:

```zig
fragment.projectAt(&projection, view, .{ .first = first, .count = 100 });
const refs = try fragment.nodesAt(.{ .first = first, .count = 100 });
```

`first` may be runtime data. `nodesAt` returns a typed `Refs` value with the same
semantic names as `Scoped(...).nodes`; use it for focus and child ownership.
Placement validates the whole namespace and its static element slots before
emitting anything. Invalid ranges fail with `NamespaceOverflow` for refs or set
the HTML writer's failure flag for projection. Keyed descendants additionally
check their calculated IDs during projection. Consumers still own cross-fragment
collision checks and must discard a failed candidate stream.

`Scoped`, its static `nodes` declarations, and module-level `project` remain
compatible. Placement reserves node IDs, not storage. The demo composes its two
control panels through a typed slot and runtime placement; browser tests retain
the slot, controls, sibling drafts and focus through independent updates.


### List fragments

Declare a list parent when compiling independent `li` rows:

```zig
addTemplate(b, .{
    .dependency = gui_dep, .owner = app, .name = "row",
    .source = b.path("row.gui.html"), .fragment_context = .ul,
});
```

Both `addTemplate` and `generateTemplate` accept `fragment_context`, an enum
with `.flow` (default), `.ul` and `.ol`. The compiler CLI accepts the equivalent
option after its output path and before any component name/path pairs:

```sh
zig-out/bin/zg-template row.gui.html generated.zig --context=ul
```

List contexts require `li` roots with whitespace-only text between them and
retain ordinary nested HTML validation. They generate only the row markup, with
no parent wrapper. The default flow context continues to reject orphan `li`
elements. Unknown contexts and invalid markup fail before opening output.

Place such fragments inside a matching `ul`/`ol` slot. Callers own matching the
actual parent to the declared context, supplying valid children, row membership
and disjoint namespaces. Projection does not inspect DOM ancestry. A list slot
has the same capacity, ownership and failure rules as a `div` slot.


## Table-section row fragments

Use `.fragment_context = .thead`, `.tbody` or `.tfoot` with `addTemplate` or
`generateTemplate` to compile standalone `tr` roots. The CLI equivalents are
`--context=thead`, `--context=tbody` and `--context=tfoot`. Cells still require
explicit rows; non-whitespace text at section level is rejected before browser
repair. Default flow fragments continue to reject orphan rows and cells.

A complete table may contain an empty `<tbody :ref="rows" :slot="$rows"></tbody>`
(or `thead`/`tfoot`) under its explicit `table`. The consumer supplies valid row
fragments, disjoint namespaces and composed snapshot capacity. Slots cannot
have competing text/children, loops or conditional ownership. No table/cell
fragment context or direct table/row slot is provided. Context is a compilation
contract; it does not insert wrappers or inspect live DOM ancestry.

### Integer layout variables

Use `<div :style-vars="$layout"></div>` with a fixed struct such as
`.{ .@"--row-gap" = @as(u32, 24), .@"--offset" = @as(i32, -2) }`.
The compiler reserves one snapshot entry; the public `template.styleVariables`
binding emits a complete `data-style-vars` attribute before publication. Names
must match `--[a-z][a-z0-9-]*`, fit 64 bytes, and number 1–16. Values must be
integers representable as i64; overflow fails the projection. The schema is fixed
for an element across updates: supply every property each time. Optional removal,
units, floats, strings and runtime names are unsupported. CSS can convert these
unitless values to lengths with `calc(var(--row-gap) * 1px)`.

Raw dynamic `data-style-vars` stays reserved and cannot coexist with this
directive. Ordinary `data-scroll-top` binding already supplies scroll positions;
consumers must admit nonnegative integer pixels up to 16,777,216, as required by
the host. Windowing and focus policy remain consumer-owned.

### Image sources

`<img src="$source" alt="$label">` binds an image source, with optional null
removal. One generated entry owns the source attribute. The public attribute
binding validates values before initial markup or patches: root-relative paths
(excluding `//`) or credential-free HTTP(S) URLs only. Empty strings, whitespace,
controls, backslashes and other schemes are rejected. Dynamic sources on other
elements remain unsupported. Consumers own URL provenance and must retain
`data-external-image="true"` when external image patches are permitted; existing
host origin checks remain in force. No image load, cache or retry policy is added.
