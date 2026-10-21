# Editorial markup, native video and static SVG gradients

Status: verified (native compiler and runtime contracts).

## Reusable contract

Compiled templates should preserve semantic editorial quotation and superscript
markup, native video elements, and common static SVG paint definitions.

Admit `blockquote` as flow content, `sup`/`sub` as phrasing content, and `video`
with ordinary static attributes and fallback flow children. Admit SVG
`linearGradient`, `radialGradient` and `stop`, retaining case-sensitive names.
Gradient containers accept only SVG stop elements; stop elements require a
gradient parent. Existing namespace, nesting, source bounds, escaping and inline
event-handler rejection remain in force. This adds no dynamic gradient attribute
API, media playback controller or external-resource fetch policy.

Consumers own content, CSS, media URLs, playback controls and accessibility.
Templates contain trusted source; untrusted text still uses escaped bindings.

## Acceptance

- [x] Semantic elements compile with normal text bindings and static attributes.
- [x] SVG gradient/stop structure compiles with preserved attribute spelling.
- [x] Invalid gradient children, misplaced stops, blockquotes in paragraphs and
  inline event handlers fail validation.
- [x] Native compiler, generated-template and runtime checks pass.

Verification: `zig build test-templates test` passes. No playback or browser
host behavior changed. Consumers verify their own styling and media behavior.
