# Request 014: bounded integer meter bindings

Status: provider verified; consumer acceptance is separate.

Support a semantic meter with explicit static nonnegative integer `min` and
`max` (u32, min < max), plus static `value` or `value="$level"`. A bound integer
must fit the declared inclusive range. Reject invalid source bounds and literal
values at compilation; reject runtime overflow or out-of-range values before
publishing a candidate projection. No clamping, floats or implicit limits.

Emit only the meter's value attribute for a level change. Retain surrounding
controls and focus. Reuse the existing host meter validation and patch protocol;
add no parser, allocation or new mutation path. Document the public binding and
verify generation, failure/retry, browser identity and demo measurements.

Verification: `npm test` passes native/compiler checks and 15 Node tests;
`npm run test:browser` passes 12 tests. Generated coverage rejects negative,
overflow and above-maximum input, verifies a one-entry snapshot and retries
short output from the prior snapshot. A valid change emits one meter value
attribute command. Browser coverage retains the meter, panel and focused input
selection and rejects invalid host values. Demo measurements remain 54,949 WASM
bytes, 2 initial pages and 3 after intentional test growth. No host change.
