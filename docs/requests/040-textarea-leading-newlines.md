# Preserve leading newlines in controlled textareas

Status: implemented and provider verified; consumer acceptance is separate.

The same controlled textarea value must survive both HTML introduction and a
later value patch. HTML parsing consumes one newline immediately after a
textarea opener; a value beginning with a newline must not lose that character.

`Projection.textareaValue` and generated `:value` bindings retain their existing
API and borrowed-value ownership. During HTML output, compensate for the parser's
initial newline handling. Do not change the value hashed into the snapshot or
sent through a `V` command. Browser-native line-ending normalization remains in
effect. No allocations, protocol commands or snapshot entries are added.

The extra output byte uses the existing bounded writer. If it exhausts capacity,
reject the candidate output and snapshot; retry from the last accepted snapshot.
Only textarea content is affected. Input values and ordinary text leaves retain
their current serialization.

Acceptance covers empty/plain values, one and multiple leading newlines, escaped
markup, initial/full recovery, H/J introductions, unchanged rerenders and V
updates. Check capacity failure/retry and retention of unaffected ancestors,
controls, focus and selection during patches.

Verification: `zig build test` and both generated-template browser tests pass.
Native coverage checks empty/plain values, leading LF/CR, escaping, unchanged
patches and output exhaustion/retry. The browser checks initial/recovery HTML,
replacement/append introductions, exact value patches and retained DOM/focus.
HTML output grows by one byte only for a value starting with LF or CR; snapshot
storage, patch bytes and allocation ownership are unchanged.
