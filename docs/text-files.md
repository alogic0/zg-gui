# Optional text-file controls

Select `.features.files = true` in `addWebApp`, or `files:true` in programmatic
`start`. The build emits a version 2 manifest and installs `gui/file-host.js`.
Version 1 manifests retain their behavior without loading this module. File
contents, example selection, source validation, filenames, errors and accepted
state remain consumer policy in Zig.

Use a single native file input with four positive integer declarations:

```html
<input type="file" accept=".txt,text/plain"
       data-text-open-kind="1" data-text-error-kind="2"
       data-text-revision="1" data-text-limit="32768">
<textarea data-node-id="3"></textarea>
<button type="button" data-text-save="3" data-text-filename="sample.txt"
        data-text-error-kind="2" data-text-limit="32768">Save</button>
```

Generated templates can bind each declaration normally; use a semantic `:ref`
for the textarea node ID. The file input must not also declare `:input`, and a
download button must not also declare a click action. This adapter owns the
browser effect and delivers ordinary `{kind,value}` input events to Zig.

`data-text-limit` bounds bytes before reading and must not exceed 262,144.
Choose it within the application's native exchange capacity. Selection accepts
one file, decodes fatal UTF-8, and delivers raw text to the open kind. Line
normalization, parsing and acceptance belong to the consumer. `accept` is only
a browser picker hint. No filename or contents are executed or interpreted.

The error kind receives exactly `too_large`, `invalid_utf8` or `read_failed`.
Cancelled pickers deliver nothing. The input value is cleared after each
selection so the same file can be selected again. Selecting a new file aborts
its prior read. Change the declared revision whenever an intervening source
edit/example change should invalidate a pending file; this aborts the old reader
and suppresses even a late completion. Removal, disabling, inert ancestry and
disposal also prevent delivery. Consumers own presentation of errors.

A download button targets exactly one connected textarea by positive numeric
node ID. It exports the current DOM value as UTF-8 `text/plain;charset=utf-8`,
including an invalid draft. Names use 1–128 ASCII letters/digits/underscore/dot/
hyphen and start with a letter or digit. Paths are rejected. The adapter bounds
UTF-8 encoding, uses a temporary anchor/Blob URL, and revokes the URL on the next
cleanup timer or disposal. Successful initiation does not acknowledge that the
user saved the file; no native success event is sent.

## Direct lifecycle API

Import `createFileHost` from `zg-gui/file-host` or installed `gui/file-host.js`:

```js
const files = createFileHost({root,onInput:event => app.setInput(event),onError});
files.sync(); // after each completed projection
files.dispose(); // before disposing the native/GUI owner
```

The host validates every declaration before accepting a sync. There are at most
16 total controls, eight pending URLs and two delegated listeners. Invalid
configuration throws; startup cleans up a failed initial sync. `onError` reports
unexpected delivery/platform failures and should not throw. `stats()` exposes
`disposed`, `controls`, `readers`, `urls` and `listeners`. Disposal is idempotent,
aborts readers/listeners, cancels timers, revokes URLs and clears records. It
leaves the projected DOM in place. Shared startup owns this lifecycle by default.

See [request 086](requests/086-text-file-host.md) for provider verification and
costs. Consumer application acceptance is separate.
