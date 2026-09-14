# SuperHTML tokenizer subset

Vendored from the exact local `superhtml-0.7.0-Y7MdPKLDJgBZWdqCE_KYn6LIA9Vua-JdwaKNJLUL0nUL`
package used by the Markdown viewer. This copy already had separate tokenizer
and template-syntax entry points; it is not assumed identical to upstream 0.7.0.
`provenance.json` records the original path and SHA-256 of each copied file.

These files are unchanged. Preserve the accompanying MIT license and copyright.
The CLI, LSP, full HTML AST, template VM, Scripty, Tracy, and CSS parser are not
included. Only build-time tools import this subset; the GUI runtime does not.

`zig build test-tokenizers` runs each module's tests as an independent root, so
tests inside imported Zig modules are not accidentally skipped.
