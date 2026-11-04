# Browser requests selected by Zig

`gui.browser.Writer` writes a bounded JSON batch into a caller-owned
`gui.html.Writer`. It is allocation-free and rejects invalid IDs, keys, duplicate
owners, more than 16 requests, and output beyond 4096 UTF-8 bytes. Call `finish`
once and check `output.failed` before publishing any model, snapshot or buffers.
A writer requires fresh output storage. Never publish partially written batches.

```zig
var output = gui.html.Writer{ .buffer = &candidate_bytes };
var browser = gui.browser.Writer.init(&output);
browser.dialog(.{ .node = nodes.dialog, .open = open,
    .cancel = @backingInt(HostEvent.cancel), .revision = dialog_ticket });
browser.focus(.{ .owner = 1, .node = nodes.heading, .revision = focus_revision });
browser.finish();
```

Construct the batch beside the candidate projection, then commit both only after
all admission succeeds. Returned byte slices borrow caller storage. Requests use
named inputs; node IDs identify unique connected HTML descendants of the mounted
root. Owners are consumer-selected positive u32 channels, independent of DOM IDs.
Revisions and event kinds are positive u32 values; closed dialogs and unsaved
scheme declarations allow revision zero. Check revision overflow in consumer
state before publishing a new request.

| Method | Inputs and behavior |
| --- | --- |
| dialog | node, open, cancel event kind, revision ticket; reconcile native showModal/close and forward cancel with the ticket |
| focus | owner, node, revision, mode, guard; once per revision, with guard always or if_body |
| scroll | owner, revision, x/y (default zero); once per revision, bounded to 16777216 |
| scheme | value light/dark, storage key, revision; reflect document theme, save only when revision is positive/new |
| frame | owner, revision ticket, event kind; one requestAnimationFrame callback per ticket |
| preferences | owner, event kind, storage key; one read while that declaration remains present |

Focus uses `gui.patch.FocusMode`: `preserve_scroll`, `nearest`, `end`; end needs a
text control. Ordinary `Projection.focus` remains available for focus within the
DOM patch stream. Browser-request focus runs after native dialog reconciliation,
which is needed when closing a modal would otherwise block the requested target.
Guards are consumed even when they decline focus, so unrelated patches never
steal focus later. Omitted focus/scroll owners release revision bookkeeping.
Keep an outstanding focus declaration until replacing its revision to retain
that idempotence across repeated projections and resync.

Storage keys admit 1–128 ASCII letters/digits/underscore/hyphen/dot. The host does
not choose preference precedence. Preference event payloads contain
`{system_dark:boolean,stored:string|null,storage_error:null|"limit"|"unavailable"}`.
Stored observations are bounded to 128 UTF-8 bytes. Scheme storage failures do
not prevent presentation. Frame and cancel payloads are `{revision:u32}`.
Consumers validate payloads and reject stale tickets and inappropriate phases.
Allow for JSON escaping in the exchange capacity: a 128-byte stored string of
control characters expands to 768 bytes before the observation's JSON fields.
A 1024-byte exchange admits every preference payload produced by this host.

## Optional main-thread host and ABI

Import `createBrowserHost` from `zg-gui/browser-host` or the installed public
`web/browser-host.js`. The optional WASM exports are `getHostBuffer()`,
`getHostLength()`, and `hostEvent(kind, payload_length)`. Events use the ordinary
exchange buffer and return the ordinary DOM render result. Existing consumers
need none of these exports; the required runtime ABI is unchanged.

```js
let app;
const browser = createBrowserHost({root, wasm: instance.exports, onError,
  onEvent: event => app.hostEvent(event)});
app = mount({root, wasm: instance.exports, onError,
  onPatch: () => browser.sync()});
// Later: browser.dispose(); app.dispose();
```

`mount`, `load`, and main-thread `createApp` return `hostEvent({kind,value})`.
Kinds are positive u32 values, values are UTF-8 strings checked against exchange
capacity. Missing optional native exports fail explicitly when used. The browser
host reads a completed accepted batch after each successful projection. Length
zero means no new batch. It validates the entire batch and all targets before
performing any operation. Unknown shapes/fields, invalid enums, duplicate owners,
missing targets, overflow and invalid UTF-8 throw through normal projection
recovery. Browser API execution can still fail after earlier operations; this is
not an atomic transaction spanning browser APIs and DOM projection.

The host reconciles native modality before focus, and viewport requests after
focus. Host events are queued as microtasks, so initialization and onPatch never
receive a reentrant business dispatch. Keep the returned app available before
yielding the mounting task. Dispose the browser host before the GUI owner.
Callbacks catch delivery errors through `onError`.

The host owns one delegated native-cancel listener, bounded revision records,
preference records, and at most one frame handle per declared frame owner.
Repeated tickets do not reschedule; omitted owners cancel pending frames and
release records. Removed/replaced dialog objects lose ownership. Dispose aborts
the listener, cancels frames, closes owned dialogs, clears records, and suppresses
queued events. `stats()` reports actual handles/records/listener ownership.
A consumer may have to issue a fresh ticket to retry a callback it rejected.

No DOM observer, timer polling, business controller, routing, selector injection,
general plugin interface or arbitrary code executor is added. The first adapter
uses main-thread WASM exports; worker transport is outside this contract. A small
pre-paint bootstrap may set presentation before WASM loads; initialized policy
and state belong in Zig.

Verification: native browser-writer tests in `zig build test`, optimized native
checks with `zig test src/root.zig -O safe --test-filter browser`, and
`zig build test-browser -Dbrowser-filter='browser requests'`. Neutral fixtures
cover modal/focus ordering, identity, guarded revisions, full resync, callback
scheduling/cancellation, blocked storage, malformed requests and disposal.
Consumer adoption and application acceptance are tracked in consumer repositories.
