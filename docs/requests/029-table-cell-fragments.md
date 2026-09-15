# Table cell fragments and row slots

Status: provider verified; consumer adoption is separate.

Allow standalone `th` and `td` roots with an explicit `tr` fragment context,
and an empty semantic row with a typed child slot. This supports independently
composed headers and cells without invalid wrappers or replacing an entire row.
Consumers retain ownership of cell membership, IDs, data and snapshot capacity.

Reject orphan cells, non-cell roots, bare text, conflicting child owners, loops
and conditional slot ownership. No direct table slot or browser ancestry
inference is added. Invalid compilation must preserve existing output. Scope and
writer failures must remain unpublished and retryable. Verify generated leaf
patches, retained table/row/sibling focus and public build/CLI entry points.

Verification: `npm test` passed native/compiler/generated checks and 25 Node
tests. Coverage includes scoped cell composition, output-failure retry,
invalid-CLI output preservation, and browser row/sibling focus retention.
No runtime host or allocation policy changes were required.
