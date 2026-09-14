# Request 005: table-section slots and row fragments

Status: implemented and verified.

Reusable tables need separately compiled rows without wrapper elements. Extend
`FragmentContext` and `--context` with `thead`, `tbody` and `tfoot`. Such fragments
must contain explicit `tr` roots and `th`/`td` children. Reject bare text and
invalid ancestors before output. Permit empty table-section `:slot` owners under
an explicit table, retaining existing restrictions on competing content owners,
loops and conditionals. The default flow context remains unchanged.

Consumers own row membership, namespace placement, snapshots, admission and
focus policy. A slot excludes its children from generated snapshot capacity.
Failed compilation preserves previous output; failed projection must not publish
partial commands or snapshots. No runtime parser or state allocator is added.

- [x] Public build options, CLI contexts and structural validation.
- [x] Generated row projection, escaped text, smallest-owner patches and overflow.
- [x] Browser table-section replacement, retained table/header and focused control.
- [x] Existing package/compiler/runtime regression checks and documentation.

Table/cell fragment contexts, implicit tbody insertion and slots directly on
`table` or `tr` are outside this request. Provider verification is separate from
consumer acceptance.


## Verification

`zig build test-templates`, `npm test` and `npm run test:browser` pass. The
independent consumer-package test uses public `addTemplate` with `.tbody`.
Generated table/row projections verify escaped text, exact text-only patches
and namespace rejection before output. Compiler/CLI tests cover all three
section contexts, invalid ancestors, bare text, competing slot ownership and
preservation of previous generated output after rejection. A host browser test
checks table/header/body identity and focus across cell text and section-child
replacement. Generated native fixtures and host browser fixtures are separate;
consumer acceptance must verify its actual composed table.

The demo remains 54,949 WASM bytes, with two initial pages and three after
intentional growth. The generated cell update emits one text command and no
HTML command. This feature changes native compilation only; no runtime protocol,
allocator or state capacity changed. Eight JavaScript tests and five browser
checks pass alongside the native/compiler/generated suites.
