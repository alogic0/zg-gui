# Optional numeric style bindings

Status: provider verified; consumer adoption is separate.

Allow `:style-vars` to receive an optional fixed-schema struct. A present value
uses the existing admitted integers and closed units; null removes the complete
`data-style-vars` attribute. Preserve the 1–16-field schema and validate all
present values before publishing. Do not accept arbitrary CSS or optional
individual fields. When this attribute clears, the host must remove the custom
properties named in its previous declaration. Other inline properties and
descendant declarations remain owned by their existing callers. Repeated removal
is a no-op. The command protocol and snapshot capacity remain unchanged.

Verify present/null/present transitions, escaped output, integer overflow before
publication, failed-output retry and leaf-only patches retaining ancestors.
Browser acceptance must inspect the CSSOM values after removal and restoration,
including retention of the affected node, ancestors, sibling focus and selection.

`npm test` passed native/compiler/generated tests and 20 Node checks. The new
native test exercises removal, failed output and successful retry without HTML
replacement. The original host checks did not cover CSSOM removal. The regression
now verifies present/null/present transitions, repeated removal, unrelated CSS
properties, descendant declarations and retained DOM identity/focus. All 20 DOM
host tests pass with `node --test tests/dom.test.mjs` after correcting removal.
