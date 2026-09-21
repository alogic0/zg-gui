# Interactive workspace showcase

Status: implemented and provider verified; this synthetic example does not
establish consumer acceptance.

Provide a complete, local project-planning example that demonstrates compiled
templates, reusable components, keyed table rows, controlled forms, SVG graphics,
derived progress and retained DOM identity. The showcase becomes the default
example page; the small introductory example remains available at basics.html.

All project data is synthetic. Example-owned Zig state handles selection,
filtering, sorting, task creation/deletion/reordering, editing, activity, reset
and theme. The browser owns native details disclosure and viewport layout.
Use only public framework APIs and the existing mount ABI. No backend, external
fonts, network services or persistence are required. Reload/reset restores the
sample; clearly explain session-only changes.

Use fixed-capacity owned text, task and activity storage. Validate UTF-8 and
capacity before copying. Publish candidate state, snapshot and output only when
both writers succeed. Reject invalid actions without state changes. Bound task
keys and list sizes; disable creation at capacity and explain empty results.

Acceptance: native state/admission tests; browser journeys for editing, search,
filters, sort/reorder, creation/deletion/reset and theme; retained row, ancestor,
form, focus and selection across scalar updates/reorder; empty states; keyboard
and mobile usability; no console errors. Include a source walkthrough and
desktop/mobile screenshots for the README. Record built size, initial/observed
memory and patch work separately from unmeasured peak memory. Static hosting
output is reviewable locally; publication depends on a repository destination.

## Verification and measurements

`zig build test-workspace` passes four native checks, including maximum escaped
text across all 24 tasks and full recovery. `npm test` passes native/compiler
checks and 37 Node tests. `npm run test:browser` passes all 29 checks. The new
browser journeys exercise the actual WASM module, retained row/ancestor/control
identity, notes focus and selection across reorder/theme/status patches, empty
states, capacity, mobile focus, static subpaths and downloadable sources.

The ReleaseSafe workspace WASM is 155,771 bytes. Its initial and observed linear
memory are both 917,504 bytes (14 pages), including a reserved 512 KiB stack and
two 128 KiB rendering buffers. Observation includes filling task capacity and
full recovery; it is not a peak stack/heap profile. Initial HTML is 27,922 bytes.
Moving the initially selected task upward emits 174 bytes in eight commands
(seven sibling moves and one status text update), with no HTML replacement.
These are example-specific measurements, not framework or consumer budgets.

Desktop, mobile and dark-theme screenshots plus a short recorded interaction
are included in the README package. Source and hosting guidance are documented
in [the showcase guide](../workspace-showcase.md). All application assets load
from relative URLs; no remote or deployment destination is configured here.
