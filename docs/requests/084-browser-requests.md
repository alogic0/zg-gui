# Bounded Zig-owned browser requests

Status: implemented and verified with neutral native and Chromium fixtures.

## Contract and ownership

Consumers need to choose focus, native dialog state, viewport scroll, color
scheme, preference initialization and frame callbacks in Zig. Browser JavaScript
executes finite requests after a successful DOM projection and supplies browser
observations as events. It must not infer business transitions from DOM content.

Provide `gui.browser.Writer`, a caller-buffered JSON batch writer, and an optional
`createBrowserHost` from the public browser-host module. The optional WASM ABI is
`getHostBuffer`, `getHostLength`, and `hostEvent(kind, payload_length)` using the
existing exchange buffer. Runtime `hostEvent({kind,value})` validates and delivers
UTF-8 event text through that ABI; applications own event kinds and parsing.

Batches contain at most 16 finite requests and 4096 UTF-8 bytes: native dialog
state/cancel-event kind, revision-owned focus (including an if-body guard),
revision-owned viewport scroll, light/dark color scheme and revision-owned
storage write, revision-owned frame callback, and one-shot color-preference read.
Node IDs, owners, event kinds and revisions are positive u32 values where used.
Focus reuses the public focus modes. Storage keys use a bounded inert vocabulary.
No arbitrary JavaScript, selectors, callbacks, URLs or markup are accepted.

Consumers build the batch alongside candidate HTML, model and snapshot, then
publish all buffers only after admission. Exhaustion and invalid arguments reject
the candidate. Borrowed bytes remain valid until the next publication. A zero
host length means no new batch. Full resync republishes current declarations;
unchanged focus/scroll/frame revisions do not repeat user-visible effects.

The host validates the whole batch and its targets before execution. Dialog state
is reconciled before focus, then viewport requests; browser events are delivered
on a later microtask, never reentrantly from onPatch. Request execution can still
fail at a browser API boundary; this is not an atomic transaction over DOM,
storage and browser scheduling. Thrown errors use existing projection recovery.
Preference read failure is reported as an observation. Storage write failure does
not reject theme presentation. Consumers choose precedence and validate values.

The host owns bounded revision records, pending frame handles and one delegated
cancel listener. Omitted frame owners cancel pending callbacks. Replaced/removed
dialog objects lose ownership; dispose cancels pending work, aborts the listener,
closes owned open dialogs and suppresses queued callbacks. Consumers reject stale
frame tickets in their Zig state and dispose the host with the GUI owner.

## Acceptance

- [x] Native checks cover JSON shape, invalid requests, capacity and retry.
- [x] Browser checks cover ordering, identity/focus, guards, frame deduplication,
      cancellation, preference errors, malformed batches, recovery and disposal.
- [x] Optional runtime event delivery works without changing required exports.
- [x] Public docs cover the optional ABI, exchange capacity and ownership.
- [x] Relevant full host/compiler regressions and resource bounds are recorded.

Pre-paint styling before WASM initialization may use a small browser bootstrap.
It is presentation only; the initialized consumer's policy remains in Zig.
Business controllers, routing, persistence policy and theme styling stay outside
the framework.

## Verification and cost record

See [the public API](../browser-requests.md). Native writer tests pass in debug
and safe modes. `zig test src/root.zig --test-filter browser -O safe` passes all
four selected tests. `zig build test-browser -Dbrowser-filter='browser requests'`
passes both selected tests, including the optional runtime ABI and retained DOM
identity/focus checks. `zig build test-all -Ddiagrams=true --summary all` passes
all 122 steps, with 190 freshly executed tests and remaining checks cached.
Final focused checks also cover duplicate owners and frame-ticket reuse.

The optional browser module is 8,942 uncompressed source bytes and has no eager
core-runtime import. The allocation-free writer uses caller storage capped at
4096 bytes plus fixed bookkeeping for 16 request identities. Host records are
bounded by the current declarations; disposal checks reach zero records, pending
frames and listeners. JavaScript heap bytes have not been measured. Browser
batch traffic is separate from DOM patch bytes and depends on consumer requests.
These bounds do not establish an application budget or authorize optimization.
Consumer adoption, application measurements and acceptance remain separate.
