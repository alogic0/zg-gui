# Retain controlled selection after option text changes

Status: implemented and provider verified; consumer acceptance is separate.

An option without a value attribute derives its native value from its text.
Changing that text can invalidate or restore a controlled select's declared
value even when the select's own snapshot has not changed.

After a `T` command updates an option, the host must restore the nearest owning
select's `data-select-value`, using the same policy as option value-attribute
and structural changes. No matching option leaves the select unselected; a later
matching option restores the declared selection. Explicit option values remain
authoritative, and selects without `data-select-value` retain native selection.

The existing public command and template APIs, snapshot capacity and failure
behavior are unchanged. Consumers own the declared value and option contents;
the host applies them to retained DOM objects. Only option text updates require
selection restoration; ordinary text leaves do not trigger a select scan.

Acceptance uses generated text-only patches with no select value patch. Verify
label swaps, disappearance and restoration of a matching value, unchanged
rerenders, explicit-value and uncontrolled selects, plus ancestor/option identity
and focused select retention.

Verification: the generated browser regression fails before the fix and passes
after it. `npm test` passes native/compiler checks and all 34 Node tests;
`npm run test:browser` passes all 26 checks, including the style, input-ordering
and textarea regressions. DOM identity, focused selection and browser drafts
remain retained.

Each patched option reapplies its owning select's declared value once without
additional commands or ancestor replacement. The demo remains 46,984 WASM bytes,
with two initial 64 KiB memory pages and three after deliberate test growth.
Peak stack/heap memory is not profiled; these demo measurements do not establish
consumer budgets or application acceptance.
