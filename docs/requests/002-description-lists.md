# Request 002: description lists

Status: implemented and verified, September 14, 2026.

Support semantic label/value layouts in templates using `dl`, `dt` and `dd`.
Accept direct terms/descriptions or div-grouped terms/descriptions. Require terms
and descriptions to belong directly to a description list or its direct div
wrapper. Reject unrelated direct list children and non-whitespace text at list
level. The existing flow-content and binding rules still apply.

- [x] Compile direct and grouped description lists, including component content.
- [x] Reject misplaced terms/descriptions and invalid direct list children.
- [x] Verify a changed description produces a text-only patch, retaining its
  list, group and sibling descriptions in native and browser checks.
- [x] Document support and measured example size/memory.

Verification: `npm test` and `npm run test:browser` pass. Native tests reject
invalid ownership and require a description value update to emit a text patch.
The browser checks the same list, description and sibling DOM objects after an
independent component update. The example WASM is 54,325 bytes (previously
53,215); initial memory remains two pages, and the explicit growth test reaches
three. Measurements include the added example markup and tracked descriptions.
