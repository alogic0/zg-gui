# Numerical chart helpers

Status: implemented and verified after diagram acceptance and dependency pinning.

## Reusable contract

Applications need numerical scales, axes and line/bar geometry that compose
with ordinary SVG templates and typed projections. Numerical chart helpers
belong to a separate public module with no diagram/parser dependency. Consumers
own data, units, descriptions, styling, selection and interaction policy.

## API, ownership and failure behavior

- Named input structs configure continuous linear scales and categorical band
  scales. Support reversed ranges, optional clamping and invertible numerical
  scales. Reject nonfinite inputs; define degenerate-domain behavior explicitly.
- Generate bounded, readable numerical ticks and axis positions/labels from
  caller-owned output storage. Specify zero crossing, negative values, empty
  domains, large/small magnitudes and capacity failure.
- Generate line paths from numerical points and bar rectangles from scaled
  categories/values. Define missing points, clipping, zero baselines, negative
  values, stable series/item keys and empty/single-point series.
- No hidden allocation or DOM ownership. Caller-owned buffers and typed SVG
  projections preserve unchanged axes, series, controls and focus. Output
  admission precedes publication; a failed update retains accepted state.
- Accessibility uses SVG names/descriptions plus a consumer-owned text/table
  alternative. Theme, responsive sizing and keyboard controls follow existing
  example patterns.

## Acceptance

- [x] Document and export scales, ticks, axes and line/bar helpers through a
  supported public module and independent consumer build.
- [x] Native tests cover mathematical invariants, signed/constant/extreme data,
  invalid floating-point values, missing points and bounded output failure.
- [x] A responsive example renders labeled line and bar series with a text
  alternative, explicit empty/error behavior and keyboard-operated updates.
- [x] Browser checks verify actual geometry, clipping, retained SVG identities,
  input focus, theme/resizing and successful recovery after rejected data.
- [x] Record artifact sizes, initial/observed peak memory and patch work for a
  stated workload; core builds require no diagram dependency.

## Delivery and measurements

The public `zg_charts` module and `zg_gui.charts` namespace expose `Linear`,
`Band`, bounded ticks/labels, four-sided `Axis` geometry, clipped line paths and
signed vertical/horizontal bars. All output storage belongs to callers and
remains unchanged on admission failure. [Public API and limits](../charts.md)
define constant/flat scales, reversed/clamped domains, missing values, stable
caller keys, zero baselines and clipping.

`zig test src/charts.zig`, `zig build test`, the independent consumer-package
checks, `zig build test-charts`, and the full browser suite with optional
diagrams enabled pass (120 native and 63 browser tests in the final runs). Geometry/identity checks cover actual signed bars,
clipped crossings, line gaps, singleton/empty series, rejected-draft recovery,
category reversal, keyboard activation, retained ancestors/focus, light/dark
themes and 390px resizing. The strict UI audit has zero findings; DESIGN.md lint
has zero errors or warnings.

The safe-mode chart example is 125,242 WASM bytes. In an isolated browser WASM
instance its initial and observed peak allocated memory are both 393,216 bytes
(6 pages) during 100 updates to eight samples, including one missing and one
negative value. Initial HTML is 14,799 bytes. A typical value update uses 243
patch bytes / 5 commands; the largest observed patch is 244 bytes. Reports and
screenshots are regenerated in `zig-out/chart-*` by the focused browser checks.
The existing core demo/workspace binaries remain 51,715 / 173,967 bytes; unused
numerical helpers add no code to them. No diagram dependency is required.
