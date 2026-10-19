# Owned CDP journeys

Status: implemented and verified in the finite checks below, October 19, 2026.

Native browser consumers need to exercise real file controls, pointer and keyboard
actions, isolated sessions, HTTP observations and downloads without a JavaScript
automation dependency. Extend the public `cdp` module; retain existing callers.

The connection owner must retain interleaved events, correlate numeric command
IDs exactly, bound frames/events and reject malformed/error replies. A browser
owner uses a fresh explicit profile and closes only its own process and targets.
Expose isolated contexts, initialization scripts, file inputs, screenshots,
downloads and network observation through named options and explicit ownership.
Pointer actions must check visibility, enabled state and hit testing before
dispatching browser input; DOM `click()` alone is insufficient. Consumers retain
their own workflow, locators, assertions and report schemas.

Verification uses neutral browser fixtures: interleaved events and command IDs,
upload bytes, completed download bytes/name, context storage isolation, blocked
origins, actual input/focus and covered/disabled rejection. Check allocator cleanup
after closing connections and joining the owned process. Application acceptance,
cross-engine support and performance claims are outside this contract.

`cdp.journey` is documented in [native browser journeys](../native-browser.md).
`zig build test-tools --summary all` passes seven tests, including case-insensitive
observed response headers and actual browser
input/upload/download, context cookie isolation, external-origin denial and
covered/disabled rejection. Protocol IDs are structurally parsed; interleaved
events/replies retain owners. General malformed-frame/fault/cancellation matrices
and exhaustive accessibility-name behavior remain outside this finite proof.
