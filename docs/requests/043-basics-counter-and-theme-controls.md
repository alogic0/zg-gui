# Basics counter and theme controls

Status: implemented and provider verified.

Complete the introductory example's counter with Decrement and Reset buttons,
and expose theme switching as a visible button in the page header. Use existing
public template action/text bindings and the mount ABI; no framework API changes.

Example-owned Zig state keeps the counter unsigned, saturates decrement at zero
and increment at its existing maximum, and resets only the count. Other state,
including theme, form values, disclosures and row order, remains intact. The
theme button names the theme it will switch to. Reload restores defaults.
Preserve existing action/input identifiers and transactional output publication;
these changes require no dynamic allocation or persistence.

Acceptance: exercise both counter directions, reset and both themes through the
real WASM host; verify that unrelated drafts, DOM ancestors, focused controls
and selection are retained. Check keyboard activation and narrow layouts.
Native checks cover zero/maximum bounds and count-only patches. Record artifact
size, observed linear memory and representative patch work; peak memory profiling
is outside this example change. Provider checks do not establish consumer
application acceptance.

## Verification

`zig build test`, `zig build`, and all three checks in
`node --test tests/browser.mjs` pass. Browser checks cover both theme directions,
keyboard activation, counter actions, retained ancestor/control identity,
focus/selection, drafts, disclosure state, and layouts at 390 and 320 pixels.

The demo WASM is 46,031 bytes. Initial and observed linear memory are 131,072
bytes through increment, decrement, reset, theme switching and full recovery.
Decrement from one to zero emits one nine-byte text command without replacing
HTML. Peak stack/heap memory has not been profiled.
