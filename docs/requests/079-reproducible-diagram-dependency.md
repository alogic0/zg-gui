# Reproducible optional diagram dependency

Status: implemented and verified after diagram hardening and consumer acceptance.

## Reusable contract

The optional diagram example must build from a complete framework checkout
without a sibling layout-engine repository. Pin a reviewed engine commit and
package hash. The fetched distribution includes its license. The core
module remains independent of this optional package. Applications may continue
to select a compatible engine through the public adapter registration helper.

Source updates require an explicit change to the package manifest. Verification
checks the resolved package before building the example. The distribution must
exclude caches, credentials, build products and Git internals.

## Acceptance

- [x] The manifest records the package revision, versioned hash and GitHub URL.
- [x] Verification rejects modified, missing or unexpected package files.
- [x] Optional native/browser and independent consumer builds pass without
  access to the original engine checkout.
- [x] Core-only builds remain independent of the optional package.
- [x] Public documentation explains ownership, update procedure and verification.

## Delivery evidence

`zig build verify-diagram-engine` checks the fetched tree against its declared
package paths, rejects symbolic links, and compares its Zig package hash to the
manifest. The diagram tests build an independent consumer with the same GitHub
revision and hash. The diagram browser suite exercises the WebAssembly example.

See [public ownership and maintenance documentation](../diagrams.md#pinned-example-engine).
