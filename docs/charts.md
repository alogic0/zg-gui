# Numerical chart helpers

Use `@import("zg_gui").charts` in an existing GUI application, or import the
standalone `dependency.module("zg_charts")` for numerical geometry alone. Neither
entry requires a diagram engine, parser, allocator or DOM host. Consumers own
data, units, categories, descriptions, keys, styling and interaction policy.

```zig
const charts = @import("zg_gui").charts;
const x = try charts.Linear.init(.{
    .domain = .{ .start = 0, .end = 12 },
    .range = .{ .start = 60, .end = 620 },
});
const y = try charts.Linear.init(.{
    .domain = .{ .start = -20, .end = 80 },
    .range = .{ .start = 300, .end = 24 },
});
var tick_values: [16]f64 = undefined;
const ticks = try charts.ticks(.{ .domain = y.domain, .output = &tick_values });
const axis = try charts.Axis.init(.{
    .scale = y, .orientation = .left, .origin = 60, .grid_length = 560,
});
var marks: [16]charts.Axis.Tick = undefined;
const positioned = try axis.writeTicks(.{ .values = ticks.values, .output = &marks });
// Project positioned[].mark/grid/label through ordinary SVG template bindings.
```

## Scales and axes

`Linear.init(.{ .domain, .range, .clamp = false })` accepts finite endpoints in
either direction. `map(value)` and `invert(position)` use wide intermediates to
avoid overflow for opposite-sign/extreme finite bounds. Unrepresentable results
return `Overflow`; IEEE rounding and underflow still apply to the f64 result.
A constant domain maps to the range midpoint and inverts to its sole value.
Otherwise a flat range cannot invert (`NonInvertibleRange`). Optional clamping
applies in both directions; extrapolation is allowed by default.

`Band.init(.{ .count, .range, .inner_padding = 0.1, .outer_padding = 0.05,
.alignment = 0.5 })` places category indices in range order. `at(index)` returns
ascending `start/end`, `center` and `width`. A reversed range reverses category
order. Inner padding and alignment must be 0…1; outer padding must be nonnegative.
Zero categories are valid, but have no valid index. A flat range or inner
padding of one produces zero-width bands. Category labels/identity are yours.

`ticks(.{ .domain, .target_count = 6, .output })` returns ascending, unique,
finite 1/2/5 decimal ticks inside the closed domain. Direction comes from the
scale, not tick order. The target (1…128) guides density; it is not an exact count.
A constant domain yields its sole value. An interval containing no nice tick
gets its midpoint. At most `max_ticks` (256) values are admitted. Zero appears
when it belongs to the selected nice-tick sequence. Subnormal and extreme
bounds are supported; output storage is never changed on failure.

`formatTick(.{ .value, .step, .buffer })` returns a shortest decimal label or
scientific notation for large/small magnitudes. It normalizes negative zero and
preserves distinct representable values rather than rounding a constant domain
to the wrong label. It allocates nothing; format units separately.

`Axis.init(.{ .scale, .orientation, .origin, .tick_size = 6, .label_gap = 6,
.grid_length = 0 })` supports top/bottom/left/right axes. `line()` supplies the
baseline; `tick(value)` supplies tick/grid segments, label position, SVG anchor
and baseline enums. `writeTicks(.{ .values, .output })` admits a bounded set
transactionally. Tick/grid lengths and label gaps are nonnegative. Label
collision handling, tick density and font size are caller decisions.

## Series

`linePath(.{ .points, .x_scale, .y_scale, .buffer, .clip = null })` accepts
`[]const ?Point`. Null points break segments. Empty input returns an empty path;
a singleton returns a move command (no visible stroke). Optional plot-rectangle
clipping computes entry/exit intersections, including segments whose endpoints
are both outside. A separate SVG `clipPath` can contain stroke thickness. With
no clip the path extrapolates; clamped scales change data geometry explicitly.
A single retained path normally uses a caller-owned series key.

`bars(.{ .data, .categories, .values, .output, .baseline = 0,
.orientation = .vertical, .clip = null })` accepts `BarDatum` values with a stable
`key`, category index and optional numerical value. It returns `Bar` values with
the same key/value and a positive-extent rectangle. Horizontal orientation swaps
the category/value axes. Positive and negative values share the chosen baseline;
a zero value retains its key with zero extent. Null values are omitted. Duplicate
keys, invalid indices and nonfinite values reject the entire result. A baseline
outside the domain extrapolates unless the value scale is clamped. Optional
clipping intersects rectangles; wholly outside bars keep their key with zero
extent. Without clipping, consumers must admit the resulting bounds themselves.

All output slices borrow caller storage. Output buffers must not overlap input
data; inputs remain immutable during a call. Numerical/geometry admission and
capacity checks precede output publication. On failure every caller output
buffer remains unchanged. Build view values first, project a candidate snapshot,
and publish application state only after all writers succeed. Ordinary keyed SVG
template loops preserve caller keys across reordering; helpers own no DOM IDs.
