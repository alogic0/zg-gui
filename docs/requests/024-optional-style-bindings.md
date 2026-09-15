# Optional numeric style bindings

Status: provider verified; consumer adoption is separate.

Allow `:style-vars` to receive an optional fixed-schema struct. A present value
uses the existing admitted integers and closed units; null removes the complete
`data-style-vars` attribute. Preserve the 1–16-field schema and validate all
present values before publishing. Do not accept arbitrary CSS or optional
individual fields. The host already removes previously applied custom properties
when this attribute clears. No host/state extension is required.

Verify present/null/present transitions, escaped output, integer overflow before
publication, failed-output retry and leaf-only patches retaining ancestors.

`npm test` passed native/compiler/generated tests and 20 Node checks. The new
native test exercises removal, failed output and successful retry without HTML
replacement. Existing host style removal and DOM identity checks also pass.
