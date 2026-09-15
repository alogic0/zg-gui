# Bounded fractional progress elements

Status: provider verified. Consumer adoption is separate.

Support semantic determinate `progress` elements with an explicit static positive
integer maximum and an explicit static or dynamically bound numeric value.
Dynamic values accept finite floating-point or integer values in [0, maximum].
Reject malformed, nonfinite and out-of-range candidates before recording a leaf.
Do not clamp values, infer completion, or own task state. Keep meter semantics
unchanged. A progress element contains phrasing content and cannot nest progress.

Emit ordinary named `value` attributes. The host validates the declared range and
retains the element, surrounding panel, focused sibling and selection. Generated
checks must exercise fractional initial/update values, rejected candidates,
failed-output retry, and compiler rejection without publishing failed output.
Indeterminate values and dynamic maxima are outside this request.

Verification: `npm test` passed native/generated/compiler checks and 20 Node
tests. Fractional updates, invalid candidates, failed-output retry and retained
DOM/focus/selection passed. No consumer acceptance is implied.
