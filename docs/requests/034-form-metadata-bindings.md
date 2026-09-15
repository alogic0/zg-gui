# Form metadata and direction bindings

Status: provider verified; consumer adoption is separate.

Allow dynamic name and autocomplete attributes on input, select and textarea,
and dynamic dir on containers. These are escaped named attribute bindings;
consumers own their values, form submission and locale policy. Do not bind or
copy control values implicitly. Absent optional metadata removes the attribute.
Retain the control, draft, selection, focus and siblings on metadata changes.

Acceptance: compiler admission rejects metadata on unrelated tags; generated
projection changes only named leaves, handles output exhaustion and retries;
browser application preserves identity, focus and selection. Consumer adoption
is separate from provider verification.

Verification: npm test passed native/compiler/generated checks and all 28 Node
checks. The generated output refusal/retry emits only dir/name/autocomplete
attributes, including removal. DOM checks preserve the draft, selection, focus,
control and siblings through metadata and input-kind changes. No allocation
policy or dependency changed.
