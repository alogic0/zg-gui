# Optional retained click actions

Status: implemented and provider-verified. Consumer adoption is separate.

A retained element may become interactive or read-only without changing its
DOM identity. Extend :on-click to accept a positive enum or optional positive
enum. Null removes data-event; a later value restores it. Keep raw event metadata
reserved in template syntax. Input kinds remain nonoptional positive enums.

The public template.event helper owns the same admission: reject zero, negative
or oversized values before publishing a candidate. Use ordinary attribute
patches; keep all application policy and keyboard semantics with consumers.
No allocation, new event listener or browser ABI is introduced. Native generated
and static rendering cover removal/restoration and retry; browser checks cover
removed-action suppression, restoration, retained ancestors and unrelated focus.
Record public API and provider results independently from consumer adoption.


## Verification and cost

`zig build test-templates test-browser -Dbrowser-filter='optional actions'`
passes the generated optional action and browser suppression/identity/focus
checks. Static HTML omits a null action; restoring a value uses an attribute
patch. Zero admission fails without accepting a new snapshot and retry works.
`zig build test-all -Ddiagrams=true --summary all` passes all 122 steps with
195 freshly executed tests, including 70 browser checks, and remaining work
cached. Public binding behavior is documented in [templates](../templates.md).

Only native projection admission changes. Browser JavaScript, listeners, native
allocation ABI and installed module selection are unchanged. One changed action
uses one A/R attribute command; unaffected owners are retained. Consumer artifact,
initial/peak memory and workload costs remain separately measured, without an
optimization or budget claim.
