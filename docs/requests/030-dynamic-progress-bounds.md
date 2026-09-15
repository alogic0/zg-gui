# Dynamic determinate progress bounds

Status: provider verified; consumer adoption is separate.

Allow a numeric maximum supplied by a Zig view for determinate progress. Both
maximum and value may be fractional. Validate the pair before publishing either
attribute: maximum must be finite and positive, value finite and in zero through
maximum. Consumers own admission, clamping, styling and progress state.

Retain static maximum compatibility. Invalid compilation preserves existing
output; invalid runtime pairs and exhausted writers remain rejectable and
retryable. Updates target only max/value attributes, retaining the progress node,
ancestors and focused siblings. No browser inference or allocation is added.

Verification: `npm test` passed native, compiler, generated projection and 26
Node tests. Cases cover fractional maxima, invalid pairs, output failure/retry,
compiler output preservation and retained DOM/focus through growing and shrinking
ranges. The existing DOM host applies the numeric attribute stream unchanged.
