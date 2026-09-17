# Merged static markup runs and out-of-line bindings

Status: provider verified; consumer adoption is separate.

Generated projections emit each static markup literal as its own `p.add`
call as the generator produces it, so an opening tag, its static attributes
and its closing `>` arrive as separate calls whenever nothing dynamic sits
between them. The binding helpers `attribute`, `text` and `event` are
generic over the projection and the bound value and were being expanded at
every call site. In a large consumer both costs scale with the number of
template elements and dominate the generated code size.

Merge consecutive static runs into one call in the compiler's final pass
and keep the three binding helpers out of line. The emitted HTML bytes,
node identities, patch streams and refusal behaviour are unchanged; only
the call count and the instantiation shape differ. Merged literals are no
longer shared as constants between templates, so the data segment grows
slightly while the code section shrinks by far more.

Acceptance: a compiler unit test merges adjacent literal lines around a node
call and leaves other lines untouched; every native, compiler and generated
check passes unchanged; the Node DOM checks pass unchanged. A consumer with
about 760 templates measured its WASM code section 265 KB smaller and its
data segment 46 KB larger, with identical rendered output and browser
acceptance.

Verification: `npm test` passed native/compiler/generated tests and all 29
Node checks on the provider revision that delivers this request.
