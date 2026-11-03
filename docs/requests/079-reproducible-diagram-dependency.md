# Reproducible optional diagram dependency

Status: implemented and verified after diagram hardening and consumer acceptance.

## Reusable contract

The optional diagram example must build from a complete framework checkout
without a sibling layout-engine repository. Pin an exact reviewed engine source
snapshot with its version, source revision, license and file digests. The core
module remains independent of this optional package. Applications may continue
to select a compatible engine through the public adapter registration helper.

Source updates are explicit and verified; builds never refresh the snapshot
implicitly. A source snapshot must exclude caches, credentials, build products
and Git internals. Provide a repeatable update/verification command and record
the tested package boundary.

## Acceptance

- [x] The checked-in snapshot has an exact revision, version and digest record.
- [x] Verification rejects modified, missing or unexpected snapshot files.
- [x] Optional native/browser and independent consumer builds pass without
  access to the original engine checkout.
- [x] Core-only builds remain independent of the optional package.
- [x] Public documentation explains ownership, update procedure and verification.

## Delivery evidence

The optional package pins version 0.9.0, revision
`37b4d4960ad85b4455fb03cc45f58164fd48bb46`, with 20 exact source-file digests
and the original LICENSE. `zig build verify-diagram-engine` runs a native
verifier; tests reject modified, missing, unexpected and symbolic-link files.
The explicit Python updater is a maintenance tool, never a build dependency.

`zig build verify-diagram-engine test-diagrams test-tools -Ddiagrams=true -j4`
and the diagram-filtered browser suite pass. An independent temporary package
outside the source tree passes optional native/consumer checks and builds the
WASM example/browser suite using only the pinned source. The same copied package
passes `zig build test -j4` with its snapshot directory removed. The unrelated
browser-tooling dependency remains available; no engine sibling path is used.

See [public ownership and maintenance documentation](../diagrams.md#pinned-example-engine).
