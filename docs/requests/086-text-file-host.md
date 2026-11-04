# Optional bounded text-file controls

Status: implemented and provider-verified. Consumer adoption is separate.

Consumers need native file selection and text download without application
JavaScript. Provide an optional `createFileHost` and shared-startup `files`
capability. Keep contents, input kinds, filenames and failure presentation in
consumer declarations. The adapter executes browser APIs only.

Connected file inputs declare positive `data-text-open-kind`,
`data-text-error-kind`, `data-text-revision` and `data-text-limit` integers.
Accept one file, bounded before reading, and decode fatal UTF-8. Deliver raw text
through ordinary `setInput`; report finite `too_large`, `invalid_utf8` or
`read_failed` error values through the declared error kind. New selection,
declaration revision change, removal or disposal cancels/suppresses old reads.
No filename or text is interpreted as code. File controls do not use data-input.

Download buttons declare `data-text-save` as the numeric node ID of a textarea,
`data-text-filename`, limit and error-kind. Export the textarea's current value
as UTF-8 text through a temporary Blob URL. Filename is a bounded inert basename.
Bound controls to 16, bytes to 256 KiB and pending URLs to eight. Validate all
declarations before accepting a sync. Own two delegated listeners, cancellable
readers and URL cleanup timers; release everything on failure/disposal.

Manifest version 2 adds an explicit boolean `files` field; version 1 remains
supported. `addWebApp` emits version 2 and installs the file module only when
selected. No file module is imported for ordinary core consumers. Startup disposes
files before native/GUI owners. Public docs and neutral browser checks cover
selection, stale reads, invalid UTF-8, limits, download content and cleanup.
Consumer adoption and application acceptance stay in consumer repositories.

## Verification and costs

The public API is documented in [text-file controls](../text-files.md).
`zig build test-browser -Dbrowser-filter='text files'` passes the selected
UTF-8, byte/control/URL limits, declaration atomicity, revision/reselection,
removal/disable, late callbacks, platform errors, exact Blob bytes and disposal
checks. `zig build test-browser -Dbrowser-filter='shared startup'` passes three
selected tests, including version 1/2 admission, optional input delivery and
failure after browser/math owners exist. A core startup requests no file module.
`zig build test-all -Ddiagrams=true --summary all` passes all 122 steps: 127
freshly executed tests (69 browser tests), with other checks cached.

The file adapter adds 6,020 uncompressed source bytes when selected. Shared
startup is 6,158 bytes; the six shared core modules total 61,423 bytes. No new
native allocation ABI is added. Each sync scans at most 16 declared controls
and retains matching reader records; read buffers are bounded by the declared
byte limit. Downloads add one temporary anchor and at most eight URLs/timers.
Disposal reaches zero controls/readers/URLs/listeners. Browser tests measure
owned counters and source bytes, not JavaScript heap or compressed transfer.
Native initial/peak memory and application DOM patch work remain consumer
measurements. These records do not authorize optimization or consumer budgets.
