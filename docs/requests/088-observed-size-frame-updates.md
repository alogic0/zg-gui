# Observed size updates outside observer delivery

Status: implemented and provider-verified; consumer adoption is separate.

An element declaring `data-observe-size` can change its layout when its
`data-size` breakpoint changes. Writing that attribute inside ResizeObserver
delivery can resize the observed element again and emit an undelivered
notifications error. Preserve the existing declaration and breakpoint meanings.

The DOM host must collect the latest measured breakpoint per element and apply
attribute changes in one animation frame outside observer delivery. Keep DOM
objects, unrelated drafts and focus. Ignore removed elements or declarations
that changed before the frame runs. Disposal must cancel queued work and
disconnect the observer; no update may run after disposal.

Use neutral browser fixtures whose breakpoint styles change their own height.
Verify initial observation and narrow/standard/wide transitions without window
errors, plus coalescing, removal and disposal with controlled observer delivery.
Consumers retain layout, breakpoint policy and error presentation. This changes
neither the projection protocol nor the WASM ABI. Attribute changes arrive on
the next animation frame; measurement and artifact costs remain separate from
application acceptance.

## Verification and cost

`zig build test-browser -Dbrowser-filter='observed sizes' -j2 --summary all`
first failed both new checks: four real observer-loop window errors and a
synchronous write where queued work was required. With frame delivery, the same
command passes all three tests (two cases and the suite root). The full
`zig build test-browser -j2 --summary all` passes 34 steps and 70 tests.
Fixtures cover changing-height breakpoints, retained input selection/draft/focus,
latest-value coalescing, detached owners, removed declarations and disposal.

The DOM module grows from 42,761 to 43,402 bytes. A host owns one pending map and
at most one scheduled frame; each observed target has at most one pending value.
A changed target receives one attribute write, without projection commands or
ancestor replacement. Disposal clears the map and cancels the frame. Native
projection code, WASM allocation and memory ABI are unchanged. The example WASM
is 51,715 bytes, SHA-256
`12e02a2333dabea7a9d97b16b6ac67125bdb6f7924755d91f62958a5551bc9cf`.
These are provider checks, without an application memory or performance claim.
