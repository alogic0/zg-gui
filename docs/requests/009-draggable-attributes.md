# Request 009: dynamic drag eligibility

Status: implemented and provider-verified. Consumer acceptance is separate.

Allow a template to bind the standard HTML `draggable` attribute on a stable
handle or row. Consumers supply the enumerated strings `true`, `false` or `auto`,
or an optional null to remove the attribute. This is an enumerated attribute,
not a Boolean presence attribute: the string `false` must remain present.
Consumers own drag actions, eligibility policy, payloads and ordering.

- [x] Admit dynamic `draggable` without admitting arbitrary event handlers.
- [x] Generate escaped initial attributes and leaf-only updates/removal with
  derived capacity and incomplete-output detection.
- [x] Verify native true/false/auto/removal transitions, compiler regressions and
  browser DOM identity/focus retention. No host protocol or allocator change.

Verification: `zig build test-templates`, `npm test` (native plus ten JavaScript
checks) and `npm run test:browser` (seven checks) pass. Generated coverage asserts
exact attribute-only commands for true/false/auto/removal and failed short output.
The browser checks drag eligibility, explicit false, removal, retained DOM
objects and sibling input focus. Demo WASM remains 54,949 bytes; memory remains
two initial pages and three after intentional growth. No runtime changes.
