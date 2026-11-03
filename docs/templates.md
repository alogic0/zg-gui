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
`$item.label` reads the current loop item. In nested loops, `$outer.name` reads
the enclosing outer loop item. Bindings must be quoted and occupy the whole
attribute value. Arithmetic, method calls, indexing and string interpolation
belong in Zig; expose their results as view fields. A leading literal dollar
sign in a static attribute can be written as `&#36;`.

| Syntax | Type and generated behavior |
| --- | --- |
| `:text="$value"` | Escaped text leaf; string, integer, bool or enum |
| `title="$value"`, `aria-expanded="$open"`, `data-theme="$theme"`, `tabindex="$index"` | Named attribute update; optional values remove the attribute |
| `colspan="$columns"`, `rowspan="$rows"` on `td`/`th` | Escaped named cell attributes; optional absence removes the attribute; callers own valid span values |
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

Controlled textarea values preserve leading newlines in initial and structural
HTML as well as value patches. The HTML serializer compensates for the browser's
first-newline handling; native line-ending normalization still applies. See
[the textarea contract](requests/040-textarea-leading-newlines.md).

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
There is no raw HTML injection, `:else`, 3-level loops, runtime expression
evaluation, or implicit persistence. Keyed loops support 2-level nesting with
derived capacity bounds and collision-free identities; inside nested loops, use
`$item` for the inner element and `$outer` for the enclosing outer element.
`:if` owns children; use `:visible` when hidden descendants must retain drafts
and focus identity. Refs inside loops are rejected because their IDs depend on
the current key.

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

Semantic `li` slots retain list items while callbacks own their flow-content
children. The item must have a valid list parent, including fragment context.
Semantic `aside` slots keep composed supplementary content as direct children.
Semantic `nav` slots keep the caller's navigation controls as direct children;
routing, active-item policy and keyboard behavior remain caller responsibilities.

Slots require an empty `div`, `section`, `aside`, `nav`, `dl`, `dd`, `ul`, `ol`, `li`, `p`, `span`, `option`, `thead`, `tbody`, `tfoot` or single `select`, may retain their subtree through
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
have competing text/children, loops or conditional ownership. An empty `tr` supports `:slot` for composed cells. Compile standalone `th`/`td`
roots with `.fragment_context = .tr` (`--context=tr` in the CLI). Bare text and
non-cell roots are rejected. No direct table slot is provided. Context is a compilation
contract; it does not insert wrappers or inspect live DOM ancestry.

### Numeric layout variables

Use `<div :style-vars="$layout"></div>` with a fixed struct such as
`.{ .@"--row-gap" = @as(u32, 24), .@"--offset" = @as(i32, -2) }`.
The compiler reserves one snapshot entry; the public `template.styleVariables`
binding emits a complete `data-style-vars` attribute before publication. Names
must match `--[a-z][a-z0-9-]*`, fit 64 bytes, and number 1–16. Values must be
integers representable as i64 or `template.StyleValue` values; overflow fails the projection. The schema is fixed
for an element across updates: supply every property each time. An optional
struct may be null to remove the entire style group; individual fields remain
required. `template.StyleValue{ .value = -12, .unit = .px }` emits `-12px`; the closed
unit enum also supports `.number` (default) and `.percent`. Values remain signed
i64 integers; consumers own range constraints such as positive dimensions.
Optional schemas/fields, floats, strings and runtime names are unsupported. CSS can also convert
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

### Select and option-group fragments

Use `.fragment_context = .select` for a group or option fragment and `.optgroup`
for option fragments inside a group. An empty `optgroup :slot="$options"` may
project its children without replacing the group. The callback owns membership,
namespace bounds and child snapshot capacity. The enclosing `select :value`
owns live selection; options use ordinary value, disabled and text bindings.
Bare text and invalid child elements are rejected in these structural contexts.

### Bounded integer meters

`<meter min="0" max="100" value="$level"></meter>` uses explicit static u32
bounds and a bound integer. `min < max` and inclusive range membership are
required. Literal values are checked during compilation; bound values are
checked during projection without clamping. Invalid values mark the candidate
HTML failed. Floats, absent bounds and nested meters are unsupported. A valid
change emits one value attribute patch, leaving controls and focus intact.
The public `template.meterValue(p, .{ .node, .min, .max, .value })` binding uses
the same checks; callers supply named integer fields and valid u32 bounds.

### Preserving externally owned node identities

Pass `Namespace.overrides = &.{.{ .local = source.nodes.control, .node = 42 }}`
with a disjoint `first`/`count` range to `Scoped`, `nodesAt` or `projectAt`.
The borrowed map uses named local refs from the unscoped generated module.
Unmapped nodes retain normal range placement. The entire range stays reserved;
only a slot's own default ID is allowed as an in-range override. Invalid maps
fail before generated output. Include all composed scopes in
`template.validateNamespaces` to reject cross-scope collisions.

### Local route links

`<a href="$path">` binds a root-relative path, query and fragment through
`template.linkHref`. Allowed characters are ASCII letters, digits and
`/._-~?&=%+#`; percent-encode other content in the consumer. Empty paths,
protocols, `//` prefixes, backslashes, whitespace and markup fail the candidate.
SVG `use href` retains its separate sprite-fragment contract.

An empty `dl` also accepts `:slot`. Its caller supplies valid description-list
children (term/value pairs or grouped pairs) and owns their capacity/membership.
The list itself remains a stable generated owner.

Use `.fragment_context = .dl` / `--context=dl` for standalone description-list
children. Grouped term/value fragments require this explicit parent context.

### Determinate progress

`<progress max="100" value="$level"></progress>` accepts finite integer or
floating-point levels between zero and its static positive integer maximum.
The compiler rejects missing or invalid static maxima, missing values, invalid static
values, block children and nested progress. Runtime bindings reject nonfinite
or out-of-range values before recording the leaf; they never clamp task state.
The host validates and applies the ordinary value attribute while retaining DOM
identity. Indeterminate progress is not supported. A dynamic `max="$maximum"` accepts a
finite positive numeric maximum, including fractions. The generated projection
validates maximum and value together before emitting either attribute; invalid
pairs invalidate the candidate output. Changes patch only max/value leaves.

Typed `p` and `span` slots require phrasing-only callback output. They support
escaped text composition without a joined-string allocation. Callback output
validity and child snapshot capacity remain the caller’s responsibility.

An `option` slot follows the same rules, with escaped text-only output and a
valid select/optgroup parent. This permits unbounded borrowed labels and short
formatted suffixes without adding a joined-string limit.

### Embedded documents

`<iframe title="Preview" sandbox="allow-scripts" src="$source"
:visible="$visible"></iframe>` compiles the frame boundary. A title and a static
sandbox attribute are required. Children, `srcdoc`, text and slot directives are
rejected. The generated `template.frameSource` binding accepts null (remove),
`about:blank`, rooted local paths and credential-free HTTP(S) URLs; it rejects
control characters, protocol-relative paths and other schemes. Image source
validation is unchanged.

The caller owns initial destinations, sandbox tokens and embedding policy. The
default host permits source patches only on sandboxed frames, for same-origin
HTTP(S) or `about:blank`; external HTTPS also requires
`data-external-frame="true"`. Source and visibility patches retain the frame
object. Navigation may replace its external document, whose contents and effects
remain outside the template renderer.

### Native field constraints

`required="$required"` accepts a Boolean on input, select and textarea.
`min="$min"`, `max="$max"` and `step="$step"` accept strings, integers or null
on input. Null removes the attribute. Input types stay static and application
validation owns admissible values; these bindings only project native constraints.
All updates retain the control and its value. See request 027.

### Explicit HTTPS links

`<a data-external-link="true" href="$destination">Open</a>` opts into
`template.externalLinkHref`, accepting a caller-approved HTTPS string or null
to remove the destination. Credentials, control characters, backslashes and
non-HTTPS schemes are rejected before publishing output. The marker is static;
ordinary dynamic anchor hrefs still require rooted local paths. See request 028.

### Same-document and explicitly permitted HTTP links

Dynamic local `href` accepts `#section-id` as well as absolute local paths.
Fragments use the same restricted ASCII syntax; a bare `#` is rejected.
`data-external-link="http"` explicitly permits HTTP or HTTPS destinations through
`externalLinkHref` with `allow_http = true`. The default marker `true` remains
HTTPS-only. Both reject credentials, unsafe characters and other schemes before
publishing an href. Consumers remain responsible for destination authorization.

Use `template.validExternalLink(.{ .value = url, .allow_http = true })` to
admit an optional resource before projecting it. Its default remains HTTPS-only.

Dynamic input `type="$kind"` uses `template.InputType`, a finite enum for text,
password, email, tel, url, search, number, date, time, datetime-local, month and
week. Pair it with the usual `:value` binding. The consumer selects a compatible
kind and owns normalization; changing kind alone patches the existing attribute.
File, checkbox, radio and submission controls retain separate static contracts.

Images with `data-object-image="true"` may bind a browser-created object URL to
`src`. Ordinary image sources retain their existing policy. The DOM host admits
blob patches only for marked images with the current origin; consumers own URL
provenance and revocation. Opaque blob origins are unsupported.


### Native dialogs

`dialog` is admitted as a flow element with normal refs, bindings and child
components. The application owns `showModal()`/`close()`, accessible naming,
initial/return focus, cancellation and state. An ordinary `data-*` binding can
communicate that state to its host; compilation adds no modal lifecycle behavior.
See [request 072](requests/072-native-dialog-templates.md).


### Editorial, media and static paint markup

Templates admit semantic `blockquote`, `sup`, `sub` and native `video` markup.
Consumers own media sources, fallback content, accessibility and playback policy.
Static SVG `linearGradient`/`radialGradient` definitions admit `stop` children;
standalone stops and non-stop gradient children are rejected. Preserve SVG name
case. See [request 073](requests/073-editorial-media-and-svg-gradients.md).

SVG charts may contain `text`, nested `tspan`, text-only `desc`, and local
`clipPath` definitions with static `clipPathUnits`. Tspans require a text/tspan
parent; labels use the normal escaped `:text` binding and retain their SVG
namespace during patches. HTML children and foreignObject remain unsupported.
Consumers own chart scales, layout, descriptions and data. See request 075.

SVG `defs` may contain `marker` definitions with preserved `refX`, `refY`,
`markerWidth`, `markerHeight` and `markerUnits`. Marker children use SVG
shapes/groups. Dynamic `marker-start`, `marker-mid` and `marker-end` accept
`none`, a local `url(#identifier)`, or an optional null for removal. Identifiers
contain ASCII letters, digits, underscores and hyphens. Consumers namespace
definition IDs for independently mounted diagrams. SVG `stroke-dasharray`,
`text-anchor`, `dx` and `dy` also accept ordinary attribute bindings.
