# Reproducible optional diagram dependency

Status: specified; follows diagram hardening and consumer acceptance.

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

- [ ] The checked-in snapshot has an exact revision, version and digest record.
- [ ] Verification rejects modified, missing or unexpected snapshot files.
- [ ] Optional native/browser and independent consumer builds pass without
  access to the original engine checkout.
- [ ] Core-only builds remain independent of the optional package.
- [ ] Public documentation explains ownership, update procedure and verification.
