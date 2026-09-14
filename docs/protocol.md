# DOM command protocol

UTF-8, one command per newline, fields separated by tabs. Empty streams are
valid. JSON string payloads escape control characters and cannot introduce a
second command. `node` is a decimal u32 owned by the application.

| Command | Fields after opcode | Behavior |
| --- | --- | --- |
| `T` | node, JSON string | Text content of one leaf |
| `V` | node, JSON string | Input, textarea or select value property |
| `C` | node, `true` / `false` | Checkbox/radio checked property |
| `A` | node, attribute, text | Set an allowed attribute |
| `R` | node, attribute | Remove an allowed attribute |
| `H` | node, JSON HTML string | Replace an owner's children |
| `J` | node, JSON HTML string | Append children without removing existing ones |
| `D` | node | Remove one owned subtree |
| `M` | node, sibling, `before` / `after` | Move between siblings, retaining DOM identity |
| `F` | node, optional `nearest` / `end` | Focus with preserved scroll, scroll-to-visible, or caret at end |

Attribute values replace tab/newline/carriage return with spaces, matching the
source protocol. Use `V` for exact form values and `T` for exact text.
ARIA states, classes, data attributes, visibility and common form attributes
are allowed. Arbitrary styles, event handler attributes and unsupported URL
schemes are rejected. `value` as an attribute is restricted to options and bounded meters.
Explicit SVG geometry/paint attributes and HTML id/for associations are allowed.
Append operations use the target element's parsing context for table and SVG children.
Controlled selects declare `data-select-value`; the host restores that declared
value after option insertion/removal/reordering and child replacement.

The host supports numeric `data-style-vars` custom properties and bounded
`data-scroll-top`. `data-value-format="instant-local"` and `data-text-format`
delegate local timezone display to the browser; canonical values remain in Zig.
Dynamic image sources require same-origin HTTP(S) or an explicit
`data-external-image="true"` declaration. Provider-specific exceptions from the
original application are not part of this protocol.

Commands execute in order. The stream is not an atomic DOM transaction: if a
later target or operation is invalid, earlier commands may already be applied.
`mount` asks Zig for `resync()` once to rebuild from canonical state and reports
the original failure through `onError`. Recovery failure propagates; there is no
retry loop. Direct `createDomHost` users must handle thrown failures themselves.
