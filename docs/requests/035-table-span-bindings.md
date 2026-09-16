# Dynamic table cell spans

Status: provider verified; consumer adoption is separate.

Allow dynamic colspan and rowspan on td and th. Treat them as escaped named
attributes, with optional absence removing the attribute. Consumers supply
valid HTML span values and own table column membership. Reject these bindings
on unrelated tags. Keep cells, rows, focused descendants and sibling identity
unchanged when only a span changes. Preserve accepted snapshots on output
refusal so callers can retry without rebuilding the table.

Acceptance: compiler tag restrictions and output preservation; generated initial
attributes and leaf-only span/removal patches, including output exhaustion and
retry. The host admits these two attribute names. No allocation or domain policy
changes are required.

Verification: `npm test` passed native/compiler/generated tests and all 29 Node
checks. The DOM table test changes/removes cell spans while retaining the table,
row, cell, focused input and draft. Compiler refusal preserves its previous
output; generated output exhaustion retries with cell attribute patches only.
