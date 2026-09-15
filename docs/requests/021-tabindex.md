# Dynamic keyboard tab order

Allow `tabindex` as a named template attribute so composite widgets can retain
buttons while moving the keyboard entry point. Reuse escaped scalar/optional
attribute bindings and leaf snapshots. Consumers choose valid HTML tab indices,
selection, keyboard handling and focus revisions; no automatic roving policy or
new host behavior is requested.

Verify generated initial/changed/removed attributes and retained DOM/focus.
Provider verification and consumer adoption remain separate.

Provider verification: `npm test` passed native/generated/compiler checks and
19 Node tests, including retained controls/focus through tab-index changes.
