# Request 011: image source bindings

Status: provider verified. Consumer acceptance is separate.

Allow dynamic `src` on `img`, including optional null removal, without admitting
it on scripts, frames or other resource-loading elements. Validate initial and
patched values through the public template binding: accept root-relative paths
(except protocol-relative paths) or credential-free HTTP(S) URLs; reject empty
values, control characters, backslashes and other schemes before publication.
Consumers own URL provenance and external-image permission. The existing host
continues to require same-origin images or explicit `data-external-image="true"`
for external source patches. No host protocol changes are required.

- [x] Derive one snapshot entry and retain image/sibling identity on updates.
- [x] Verify escaped initial sources, null removal, invalid URLs and short output.
- [x] Reject dynamic sources on non-image elements at template compilation.
- [x] Verify browser image source changes preserve sibling focus and DOM identity.

Verification: `zig build test-templates`, `npm test` (12 Node tests plus native
checks) and `npm run test:browser` (9 tests) pass. The fixture derives one snapshot
entry and emits a single source attribute update/removal, without HTML replacement.
The standalone demo remains 54,949 bytes, initially 2 WASM pages and 3 after
intentional test growth. Consumer acceptance is not established by these checks.
