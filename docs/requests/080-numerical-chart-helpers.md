# Numerical chart helpers

Status: specified; follows diagram acceptance and dependency pinning.

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

- [ ] Document and export scales, ticks, axes and line/bar helpers through a
  supported public module and independent consumer build.
- [ ] Native tests cover mathematical invariants, signed/constant/extreme data,
  invalid floating-point values, missing points and bounded output failure.
- [ ] A responsive example renders labeled line and bar series with a text
  alternative, explicit empty/error behavior and keyboard-operated updates.
- [ ] Browser checks verify actual geometry, clipping, retained SVG identities,
  input focus, theme/resizing and successful recovery after rejected data.
- [ ] Record artifact sizes, initial/observed peak memory and patch work for a
  stated workload; core builds require no diagram dependency.
