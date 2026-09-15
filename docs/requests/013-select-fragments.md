# Request 013: select and option-group fragments

Status: provider verified; consumer acceptance is separate.

Allow explicit `select` and `optgroup` fragment contexts. An option may be
compiled independently and projected into the correct parent; a group may be
compiled in a select context. Permit an empty optgroup to delegate children to a
typed slot. Retain existing controlled-select ownership, escaping, namespaces,
caller-owned membership and capacity, and atomic failure behavior.

Reject orphan options, nested groups, non-option group children, bare structural
text and competing slot owners. No dynamic selected attribute is introduced:
the enclosing controlled select owns live selection.

Verify compiler validation, generated leaf updates, short-output retry and
browser select/option/sibling identity and focus. Run native/compiler, package
and host checks. Record demo artifact/memory measurements; no budget changes.

Verification: `npm test` passes native/compiler checks and 14 Node tests;
`npm run test:browser` passes 11 tests. Generated option label changes emit only
one text command; short output fails and retry uses the unchanged snapshot.
Browser coverage retains the option for leaf updates and the group, select,
sibling and focus through child replacement. The demo remains 54,949 WASM bytes,
2 initial pages and 3 after intentional growth. No runtime change was needed.
