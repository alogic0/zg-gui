# Workspace retention across demo navigation

Status: implemented and provider verified.

## Contract and ownership

The synthetic workspace must retain admitted task changes when navigating to
another demo page and returning, or reloading the same tab. Preserve task IDs,
fields, manual order, selection, filters, sort, font size and recent activity.
An empty workspace and task deletions must also remain empty/deleted. Reset
explicitly restores the sample and replaces the saved state. Theme preference
continues to use the separate shared appearance mechanism.

The example owns persistence; no framework runtime or public ABI changes.
Use a bounded, versioned data snapshot owned and validated by Zig, not a copy of
WASM memory or DOM. Export/import hooks are example-specific, documented in the
showcase guide. The browser uses the public mount API and sessionStorage scoped
to the example's base path. Save admitted state synchronously after mutations.
The snapshot buffer is borrowed until the next export/import; import copies all
variable text into owned state before publishing. Reject unsupported versions,
truncated or oversized payloads, invalid UTF-8/enums, duplicate/out-of-range
keys, invalid selection and other broken bounds without partial state changes.
Do not restore stale focus commands or theme state from the task snapshot.

Restore before mounting, avoiding a visible sample-state flash or mobile focus
jump. Storage failures keep the live workspace usable and display an honest
save-status message. Invalid snapshots fall back to the sample with a notice.
Storage is per tab and survives navigation/reload, not guaranteed after tab
closure; this is not backend or cross-device saving. Dispose example resources.

## Acceptance

- Native round-trip and malformed snapshot tests, including all 24 tasks at
  maximal text capacity and restore buffer ownership.
- Real-WASM browser navigation through Basics and Source, reload, edits, reorder,
  deletion, empty-state and reset persistence; bounded capacity and unique IDs.
- No regression in retained DOM/focus; storage denied/quota failure/corruption
  leaves the page usable with accurate feedback.
- Document format ownership, limits and measured WASM size, linear memory and
  patch work. Provider checks do not establish consumer acceptance.

## Verification

`zig build test-workspace` passes all seven native checks, including full-capacity
snapshot round trips, owned UTF-8 text and atomic malformed-input rejection.
`npm run test:browser` passes all 37 browser/artifact checks. Existing retained
DOM, focus, contrast, mobile navigation and size checks remain green. JavaScript
syntax, `zig fmt --check` and `git diff --check` pass. The two session journeys
pass again after the final empty-patch persistence refinement.

The new browser journeys create and edit a task, visit Basics and Source, return,
and reload. They verify fields, order, stable IDs, selected task, filters, sort,
font size and activity; deletion, empty-state and reset persistence; capacity;
separate tab state; hidden-row reorders with empty DOM patches;
corrupt/oversized snapshots; and denied/quota-limited storage.
The save-status message was inspected in the mobile detail panel after navigation.

Workspace WASM is 169,043 bytes (+11,165). Initial/observed linear memory remains
917,504 bytes; the 32 KiB snapshot buffer fits within those reserved pages.
Initial HTML is 28,641 bytes. Reordering retains the same eight commands / 174
bytes and preserves existing DOM. Peak stack/heap memory remains unprofiled.
Closing a tab ends the retention guarantee; browser session recovery may restore
sessionStorage. Storage rejection is surfaced rather than claiming successful
saving. This is example/provider verification, not consumer acceptance.
