# Request 008: explicit radio value input

Status: implemented and provider-verified; consumer acceptance is separate.

A radio group can share one typed input kind while identifying the selected
choice through its value. Allow `data-value-format="value"` on a static radio
with `:input`. Keep existing implicit checked-state behavior for compatibility.
The host's ordinary value input path already supports this mode; no runtime
protocol or selection policy changes are needed. The consumer owns group state
and supplies each radio's `:checked` binding.

- [x] Accept the explicit literal radio value mode without adding a competing
  checked-format attribute. Retain default radio and checkbox checked behavior.
- [x] Reject unsupported overrides on checkbox inputs and invalid/dynamic modes.
- [x] Verify generated checked leaves, exact output, capacity and failed output;
  verify radio payload, identity and focus through the existing host.
- [x] Document the mode and run provider compiler/package/browser checks.

Verification: `zig build test-templates`, `npm test` (native and ten JavaScript
checks), and `npm run test:browser` (seven checks) pass. Compiler and generated
fixtures cover compatibility, checked-only patches, derived capacity and
truncated output. A browser host fixture verifies choice payloads, checkbox
compatibility, retained radio/fieldset identity and focused checked updates.

No runtime or allocation code changed. The demo remains 54,949 WASM bytes, two
initial pages and three pages after intentional growth. Provider checks do not
establish any consumer's business behavior or acceptance.
