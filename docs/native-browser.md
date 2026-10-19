# Native browser journeys

Import the public `cdp` build module and use `cdp.journey.Browser.start(allocator,
io)` for an owned headless Chromium process. Allocate a journey in an arena;
close each `Page`, call `Browser.stop()`, then destroy the arena. The browser
creates an exclusive temporary profile, discovers its own ephemeral debug port,
and removes that profile after joining its process. Each `browser.page(origins)`
creates a separate browser context. The allowlist contains exact HTTP origins.

`Page` exposes navigation, initial document scripts, JSON-valued evaluation,
observed requests, screenshots and completed downloads. `mark()` followed by
`response(.{ .after, .method, .path })` correlates actual observed HTTP traffic.
`responseAny(matches)` returns the first observed matching response when a
workflow can take several paths. `Request.header(name)` performs case-insensitive
HTTP header lookup while preserving the observed spelling in `headers`.
`download(control, output)` activates the control and requires a completed browser
download before returning its suggested filename and exact bytes. Consumers own
the destination file, report redaction and workflow assertions. Request captures
may contain credentials and must not be dumped wholesale.

Locators support CSS, scoped roles with names, form labels and visible text.
Their name computation covers labels, aria-label/labelledby and text content; it
is a bounded helper, not a complete accessibility-name implementation. Ambiguous
actions fail. `click` checks visibility, enabled state, center-point hit testing
and stable geometry across animation frames after hover, then uses browser mouse
input. `waitEnabled` waits for an operable visible control. `fill` selects a form value and uses browser text
input. `file` uses the protocol's file-input command. `handle` retains an actual
DOM object for identity assertions. Browser-side JS performs DOM queries only;
native callers own scenario state and sequencing.

Explicit navigation/reload accepts its `beforeunload` confirmation. Other native
dialogs are dismissed and fail the journey. A failed wire command seals its
connection; callers must close it rather than reuse a partially read frame.

Frames and retained messages are bounded to 64 MiB; pending messages to 8,192;
observed requests to 20,000. Socket reads have a 30-second timeout. Callers use
one task per connection; connection event callbacks may issue nested commands.
Numeric IDs are matched structurally and unmatched events/replies are retained.
`WsSession.takeEvent()` transfers ownership of an unhandled event to its caller.

Verification: `zig build test-tools` includes real file/input/download, context
cookie isolation, origin denial and covered/disabled-action rejection, with the
testing allocator backing a released arena. This does not establish every arena
borrow, all accessibility semantics, whole-process browser memory or performance.
