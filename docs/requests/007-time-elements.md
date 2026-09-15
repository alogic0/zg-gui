# Request 007: semantic time elements

Status: implemented and provider-verified; consumer acceptance is separate.

Allow semantic `time` elements in template flow and phrasing content, including
inside table cells. Preserve literal host formatting attributes and support
escaped text and optional `datetime` attribute bindings. Values are supplied by
the consumer; parsing, timezone conversion and date validation remain consumer
policy. Dynamic host formatting directives remain reserved.

- [x] Compiler validation accepts time in valid HTML contexts and still rejects
  invalid table/list/select structure and block content in phrasing containers.
- [x] Generated text and datetime changes target only the time element, retain
  surrounding controls, derive capacity and reject incomplete output.
- [x] Run compiler/package regression tests and document the public capability.

This is a compiler extension with no runtime, allocation or protocol change.
Provider verification is separate from consumer acceptance.

Verification: `zig build test-templates`, `npm test` (native and nine JavaScript
checks), and `npm run test:browser` pass. Generated native coverage verifies
escaped content, exact text/attribute-only patches, derived capacity and output
failure. Existing host browser regressions retain controls and focus; this
extension adds no host behavior. Demo WASM remains 54,949 bytes, with two initial
pages and three after intentional growth. No new runtime allocation is added.
