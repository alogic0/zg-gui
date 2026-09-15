# Typed dynamic input kinds

Status: provider verified; consumer acceptance is separate.

Allow a retained input to select its native text, secret, email, phone, URL,
search, numeric or temporal kind through a finite Zig enum. Compile dynamic type
bindings only on inputs. Preserve the same control, value and sibling; changing
kind alone emits a type attribute patch. Keep file, checkbox, radio and submit
contracts separate. Reject unsupported kinds at compile time and conflicting
checked bindings at template compilation. Verify exhausted output and retry.

Verification: `npm test` passed native/compiler/generated checks and 27 Node
checks. Generated output exhaustion/retry emits only the input type attribute;
browser coverage retains input/value, parent, sibling, focus and selection
through text/password changes. No host behavior changed.
