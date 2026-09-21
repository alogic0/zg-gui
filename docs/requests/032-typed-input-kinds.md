# Typed dynamic input kinds

Status: provider verified; consumer acceptance is separate.

Allow a retained input to select its native text, secret, email, phone, URL,
search, numeric or temporal kind through a finite Zig enum. Compile dynamic type
bindings only on inputs. Preserve the same control, value and sibling; changing
kind alone emits a type attribute patch. Keep file, checkbox, radio and submit
contracts separate. Reject unsupported kinds at compile time and conflicting
checked bindings at template compilation. Verify exhausted output and retry.

When kind and controlled value change together, generated projections must apply
the type before writing the value, independent of template attribute order.
The browser applies native sanitization for the new kind; consumers own value
validity. No new protocol commands, allocations or snapshot entries are needed.
Acceptance covers number/text transitions with both attribute orders, unchanged
rerenders and retained input, ancestor, sibling and focus.

Verification: `npm test` passed native/compiler/generated checks and 27 Node
checks. Generated output exhaustion/retry emits only the input type attribute;
browser coverage retains input/value, parent, sibling, focus and selection
through text/password changes. No host behavior changed.

Regression verification: `zig build test-templates` and the compiler, independent
package and generated-template DOM tests pass. The browser test consumes actual
generated full/patch output for both attribute orders, verifies number/text
transitions and an unchanged rerender, and retains ancestors, controls and focus.
