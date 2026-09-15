# Typed phrasing-container slots

Status: provider verified; consumer adoption is separate.

Allow an empty `p`, `span` or `option` to compose a typed `:slot`. This supports streamed
escaped text and separately scoped inline fragments without allocating a joined
string or changing semantic tags. Callbacks must emit phrasing content valid for
the owner. An `option` callback must emit escaped text only. They own bounded output and child snapshot contributions; the compiler
cannot inspect callback output, as with existing typed slots.

Reject competing static text, children, text bindings, conditions and loops.
Keep scope, admission and mutation ownership unchanged. No raw markup binding or
runtime parser is introduced. Verify compiler rejection, generated escaped child
leaves, failed-output retry, retained sibling focus and existing host checks.

`npm test` passed compiler/native/generated checks and 20 Node checks. A
generated paragraph/span fixture also projects a text-only option, proves
escaping and retained child leaves, and retries failed output. Existing generic
host identity/focus checks pass; no runtime or persistent state was added.
