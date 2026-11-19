# Reproducible template tokenizer builds

The native template compiler and formatter need HTML tokenization and directive
recognition from a reproducible source. Pin the SuperHTML Git revision and Zig
package hash in the framework manifest. A clean checkout must be able to build
both tools and generate WebAssembly projections using the documented template
syntax. Zig must reject fetched source that fails the package hash check.

The native tools own parsing and diagnostics. Consumers use the framework's
compiler artifact and generated Zig code. Keep the tokenizer out of the
WebAssembly runtime and keep its license available with the native tools.

Verify the three tokenizer module roots with `zig build test-tokenizers`. Run
the template tests, including the separate package that compiles its own
template, and build the framework from an empty package cache.

## Verification

With Zig 0.17.0 on Linux, `zig build` succeeded from an empty cache and
`zig build test-all` passed all 317 tests, including all seven tokenizer tests.
An independent package fetched a framework archive and used `addTemplate` to
render its own template. Zig rejected a deliberately changed SuperHTML hash.
The demo, workspace, and charts WebAssembly binaries matched the previous
build byte for byte.
