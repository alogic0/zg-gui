# Explicit object image sources

Status: provider verified; consumer acceptance remains separate.

Allow an image template to opt into browser-created blob URLs through a static
`data-object-image="true"` marker. Keep ordinary source admission unchanged.
The Zig binding accepts non-opaque HTTP(S)-origin blob URLs and rejects malformed,
credentialed, data, executable or opaque sources before publishing output. The
DOM host requires the current origin and explicit image permission for patches.
The caller owns creation, provenance, lifetime and revocation. Preserve image,
sibling and focus; verify optional removal, failed output and retry.

Verification: `npm test` passed native/compiler/generated checks and 28 Node
checks. Generated coverage includes refusal, null sources and failed-output
retry. A browser-created image loads through a retained node; unmarked, foreign
and opaque blob patches are refused, and removal retains sibling focus.
