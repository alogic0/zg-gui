# Request 010: integer style variables

Status: implemented and provider-verified. Consumer acceptance is separate.

Compiled fragments need numeric layout parameters without raw inline CSS or
runtime string construction. Add `:style-vars="$layout"` for a struct of fixed
CSS custom-property names and integer values, for example
`.{ .@"--row-gap" = @as(u32, 24) }`.

The public binding accepts 1–16 fields, names matching `--[a-z][a-z0-9-]*` up to
64 bytes, and integers representable as i64. It emits one `data-style-vars`
attribute through the existing projection adapter. Field names are fixed by the
view type; every projection supplies all values. No optional removal, floats,
units, arbitrary CSS, strings or dynamic property names are admitted in this slice.
Use stylesheet calculations to convert unitless values to lengths.

- [x] Derive one snapshot entry per binding and retain the element and siblings.
- [x] Reject invalid schema at compile time and integer overflow before emitting
  the attribute; preserve output-capacity failure and retry semantics.
- [x] Reject raw dynamic `data-style-vars` and conflicts with the directive.
- [x] Verify generated initial/patch output and browser CSS application with
  sibling input focus and identity retained. Existing scroll bindings remain.

The host protocol and style policy remain unchanged. Consumers own layout,
windowing, scroll policy and admission of domain data.

Verification: `zig build test-templates`, `npm test` (11 JavaScript checks),
expanded negative-binding CLI tests (4 checks), and `npm run test:browser`
(8 checks) pass. The style fixture verifies exact attribute-only updates, signed
values, runtime overflow and short-output retry. Negative fixtures cover invalid
names, empty schemas and string values. Browser coverage applies numeric spacer
and scroll updates while retaining the scroller, spacer and focused input.
Demo WASM remains 54,949 bytes; memory remains two initial pages and three
after intentional test growth. No host changes or performance claim.
