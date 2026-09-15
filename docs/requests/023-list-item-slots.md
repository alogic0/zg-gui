# Typed list-item child slots

Status: provider verified. Consumer adoption remains separate.

Support an empty semantic `li` with a typed `:slot` callback, including list
fragments. A consumer may retain a list item while independently projecting its
flow-content descendants. The existing namespace, snapshot, output failure and
smallest-owner rules apply. This is compiler composition support; membership,
selection, focus policy, event dispatch and business state remain consumer-owned.

Reject conflicting static content, text, conditions and loops exactly as for
other flow slots. Preserve required list parents. Slot descendants remain the
callback's responsibility and are excluded from the parent's generated capacity.
No new host command, raw-HTML binding or child inference is introduced.

Verify generated initial output, escaped leaves, retained ancestor patch output,
failed-output retry, invalid compositions and existing host list identity/focus
coverage. Provider delivery does not imply consumer acceptance.

`npm test` passed compiler, native and generated projection checks plus 20 Node
tests. The generated list-item fixture proves escaped child output, a text-only
patch retaining its list/item ancestors, and retry after failed output. Existing
DOM list checks retain row controls and focus across typed updates and reordering.
No runtime code or persistent provider state was added.
