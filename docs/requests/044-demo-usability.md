# Demo readability and guided interactions

Status: implemented and provider verified.

Make the synthetic examples understandable as a connected library showcase.
Use existing public templates, projections and runtime APIs. Example-owned Zig
state continues to own application data; example browser code may own viewport
navigation and focus return. No framework or consumer policy changes are needed.

Required behavior:

- Visible Showcase, Basics and Source navigation at desktop and mobile widths,
  with consistent typography, color tokens and theme-button treatment.
- Readable default workspace text, sufficient normal-text contrast in both
  themes, comfortable interaction targets and wrapping at narrow widths and
  every supported font-size setting. Do not disguise static content as controls.
- Explain what to try and what it demonstrates near each example, with source
  links. Distinguish session-only edits from persistent saving.
- Reverse the entire visible Basics row collection. Row membership/reordering
  must not alter channel options. Demonstrate removing Email through a separate,
  explicitly named control; explain unavailable selections and their recovery.
  Keep the two channel selections independent and preserve drafts in retained
  rows. Missing options remain controlled values, rather than silently selecting
  another channel. SVG markers remain visible in either theme.
- Bring the mobile task editor into view on entry. Back to tasks restores focus
  to the selected visible row, or the search field if that row is filtered out.
  Preserve edits, filters and DOM identity. Remove browser listeners on disposal.

Retain action/input identifiers, bounded storage and transactional rendering.
New actions are appended. Verify maximal full projections still fit their
buffers; reject failed output without publishing candidate state. Browser-only
navigation must not change Zig data or require internal framework APIs.

Acceptance: native state and maximum-admission checks; real-WASM browser checks
for independent selections, full row reversal, focus/selection/draft retention,
mobile editor round trips, shared navigation under a static subpath, keyboard
controls, contrast and supported text sizes; inspect fresh desktop/mobile and
dark screenshots. Record artifact size, initial/observed memory and patch work;
unmeasured peak memory and real-device/screen-reader testing remain explicit
limits. Provider verification does not establish consumer acceptance.


## Verification

`npm test` passes native/compiler checks and all 40 Node checks.
`npm run test:browser` passes all 32 browser/artifact checks. After the final
Basics layout adjustment, the five directly affected Basics/usability checks
also pass. `zig fmt`, JavaScript syntax checking and `git diff --check` pass.

The new checks cover channel-option independence, complete three-row reversal,
explicit unavailable-option messaging and recovery, current source downloads,
shared navigation under a static subpath, narrow-layout text/control sizes and
normal-text contrast in both themes. Existing checks continue to verify retained
DOM, drafts, focus and selection. Mobile editor return tests cover both a visible
selected row and a filtered-out row, and disposal removes example listeners.
Widths 320–1440 pixels and the largest supported font setting have no page
horizontal overflow. On the narrowest screens, task status follows the task
name rather than squeezing both into small columns. Screenshots were inspected
for desktop, mobile, editing and both themes; README images and the interaction
recording were refreshed.

| Artifact | WASM bytes | Initial / observed linear memory | Initial HTML bytes |
| --- | ---: | ---: | ---: |
| Basics | 50,849 | 131,072 / 131,072 | 8,420 |
| Workspace | 157,373 | 917,504 / 917,504 | 28,138 |

Basics observation includes adding a row, removing Email and full recovery.
Workspace observation includes filling all 24 task slots and full recovery.
The counter increment emits one nine-byte text command; moving the selected
workspace task up emits 174 bytes in eight commands. Neither replaces HTML.
Peak stack/heap memory remains unprofiled. Browser contrast checks cover the
examples' opaque text/background pairs; this is not a full accessibility audit.
Screen readers and real mobile keyboards still require device-level assessment.
