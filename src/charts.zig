//! Allocation-free numerical geometry. Callers own SVG nodes, keys and data policy.
const std = @import("std");
pub const Error = error{ NonFinite, Overflow, InvalidPadding, IndexOutOfBounds, NonInvertibleRange, InvalidTickCount, CapacityExceeded, InvalidGeometry, DuplicateKey };
pub const Interval = struct { start: f64, end: f64 };
pub const Point = struct { x: f64, y: f64 };
pub const Segment = struct { start: Point, end: Point };
pub const Rect = struct { x: f64, y: f64, width: f64, height: f64 };
fn finite(values: []const f64) Error!void {
    for (values) |v| if (!std.math.isFinite(v)) return error.NonFinite;
}
fn narrow(value: f128) Error!f64 {
    const result: f64 = @floatCast(value);
    if (!std.math.isFinite(result)) return error.Overflow;
    return result;
}
fn interpolate(input: struct { value: f64, from: Interval, to: Interval, clamp: bool }) Error!f64 {
    try finite(&.{ input.value, input.from.start, input.from.end, input.to.start, input.to.end });
    const a: f128 = input.from.start;
    const b: f128 = input.from.end;
    var t: f128 = if (a == b) 0.5 else (@as(f128, input.value) - a) / (b - a);
    if (input.clamp) t = std.math.clamp(t, 0, 1);
    return narrow((1 - t) * @as(f128, input.to.start) + t * @as(f128, input.to.end));
}

pub const Linear = struct {
    domain: Interval,
    range: Interval,
    clamp: bool = false,
    pub const Options = struct { domain: Interval, range: Interval, clamp: bool = false };
    pub fn init(input: Options) Error!Linear {
        try finite(&.{ input.domain.start, input.domain.end, input.range.start, input.range.end });
        return .{ .domain = input.domain, .range = input.range, .clamp = input.clamp };
    }
    /// A constant domain maps to the range midpoint. Finite extrapolation is allowed.
    pub fn map(self: Linear, value: f64) Error!f64 {
        return interpolate(.{ .value = value, .from = self.domain, .to = self.range, .clamp = self.clamp });
    }
    /// A constant domain inverts to its sole value; a flat range is otherwise ambiguous.
    pub fn invert(self: Linear, value: f64) Error!f64 {
        try finite(&.{ value, self.domain.start, self.domain.end, self.range.start, self.range.end });
        if (self.domain.start == self.domain.end) return self.domain.start;
        if (self.range.start == self.range.end) return error.NonInvertibleRange;
        return interpolate(.{ .value = value, .from = self.range, .to = self.domain, .clamp = self.clamp });
    }
};

pub const Band = struct {
    options: Options,
    pub const Options = struct { count: usize, range: Interval, inner_padding: f64 = 0.1, outer_padding: f64 = 0.05, alignment: f64 = 0.5 };
    pub const Span = struct { start: f64, end: f64, center: f64, width: f64 };
    pub fn init(input: Options) Error!Band {
        try finite(&.{ input.range.start, input.range.end, input.inner_padding, input.outer_padding, input.alignment });
        if (input.inner_padding < 0 or input.inner_padding > 1 or input.outer_padding < 0 or input.alignment < 0 or input.alignment > 1) return error.InvalidPadding;
        return .{ .options = input };
    }
    /// Category order follows range direction; each returned span has start <= end.
    pub fn at(self: Band, index: usize) Error!Span {
        const o = (try init(self.options)).options;
        if (index >= o.count) return error.IndexOutOfBounds;
        const low: f128 = @min(o.range.start, o.range.end);
        const size: f128 = @as(f128, @max(o.range.start, o.range.end)) - low;
        const count: f128 = @floatFromInt(o.count);
        const step = size / @max(1, count - @as(f128, o.inner_padding) + 2 * @as(f128, o.outer_padding));
        const offset = (size - step * (count - @as(f128, o.inner_padding))) * @as(f128, o.alignment);
        const ordinal = if (o.range.end < o.range.start) o.count - 1 - index else index;
        const start = low + offset + step * @as(f128, @floatFromInt(ordinal));
        const width = step * (1 - @as(f128, o.inner_padding));
        return .{ .start = try narrow(start), .end = try narrow(start + width), .center = try narrow(start + width / 2), .width = try narrow(width) };
    }
};

pub const max_ticks = 256;
pub const TickOptions = struct { domain: Interval, target_count: usize = 6, output: []f64 };
pub const Ticks = struct { values: []const f64, step: f64 };
fn power10(exponent: i32) f128 {
    var result: f128 = 1;
    for (0..@intCast(@abs(exponent))) |_| result = if (exponent < 0) result / 10 else result * 10;
    return result;
}
/// Ascending 1/2/5 decimal ticks inside the closed domain, independent of direction.
/// Admission is transactional: failure leaves output unchanged. At most 256 ticks.
pub fn ticks(input: TickOptions) Error!Ticks {
    try finite(&.{ input.domain.start, input.domain.end });
    if (input.target_count == 0 or input.target_count > 128) return error.InvalidTickCount;
    var values: [max_ticks]f64 = undefined;
    var count: usize = 0;
    const low: f128 = @min(input.domain.start, input.domain.end);
    const high: f128 = @max(input.domain.start, input.domain.end);
    var step: f128 = 1;
    if (low == high) {
        values[0] = input.domain.start;
        count = 1;
    } else {
        const rough = (high - low) / @as(f128, @floatFromInt(@max(input.target_count - 1, 1)));
        const approx: f64 = @floatCast(std.math.clamp(rough, @as(f128, std.math.floatTrueMin(f64)), @as(f128, std.math.floatMax(f64))));
        const base = power10(@intFromFloat(@floor(@log10(approx))));
        const fraction = rough / base;
        step = @max(base * @as(f128, if (fraction <= 1) 1 else if (fraction <= 2) 2 else if (fraction <= 5) 5 else 10), @as(f128, std.math.floatTrueMin(f64)));
        const first = @ceil(low / step);
        const last = @floor(high / step);
        var index = first;
        while (index <= last) : (index += 1) {
            const value = try narrow(index * step);
            if (value < low or value > high) continue;
            if (count != 0 and values[count - 1] == value) continue;
            if (count == values.len) return error.CapacityExceeded;
            values[count] = if (value == 0) 0 else value;
            count += 1;
        }
        if (count == 0) {
            values[0] = try narrow((low + high) / 2);
            count = 1;
        }
    }
    if (input.output.len < count) return error.CapacityExceeded;
    @memcpy(input.output[0..count], values[0..count]);
    return .{ .values = input.output[0..count], .step = @floatCast(@min(step, @as(f128, std.math.floatMax(f64)))) };
}

pub const LabelOptions = struct { value: f64, step: f64, buffer: []u8 };
/// Shortest decimal/scientific labels, preserving distinct representable ticks.
pub fn formatTick(input: LabelOptions) Error![]const u8 {
    try finite(&.{ input.value, input.step });
    if (input.step <= 0) return error.InvalidTickCount;
    var memory: [384]u8 = undefined;
    const value = if (input.value == 0) @as(f64, 0) else input.value;
    const scientific = (value != 0 and (@abs(value) < 0.0001 or @abs(value) >= 1e7)) or input.step < 1e-6;
    const result = if (scientific) std.fmt.bufPrint(&memory, "{e}", .{value}) else std.fmt.bufPrint(&memory, "{d}", .{value});
    const text = result catch return error.CapacityExceeded;
    if (text.len > input.buffer.len) return error.CapacityExceeded;
    @memcpy(input.buffer[0..text.len], text);
    return input.buffer[0..text.len];
}

pub const Axis = struct {
    options: Options,
    pub const Orientation = enum { top, bottom, left, right };
    pub const Anchor = enum { start, middle, end };
    pub const Baseline = enum { auto, hanging, middle };
    pub const Options = struct { scale: Linear, orientation: Orientation, origin: f64, tick_size: f64 = 6, label_gap: f64 = 6, grid_length: f64 = 0 };
    pub const Tick = struct { value: f64, position: f64, mark: Segment, grid: Segment, label: Point, anchor: Anchor, baseline: Baseline };
    pub fn init(input: Options) Error!Axis {
        _ = try Linear.init(.{ .domain = input.scale.domain, .range = input.scale.range, .clamp = input.scale.clamp });
        try finite(&.{ input.origin, input.tick_size, input.label_gap, input.grid_length });
        if (input.tick_size < 0 or input.label_gap < 0 or input.grid_length < 0) return error.InvalidGeometry;
        return .{ .options = input };
    }
    pub fn line(self: Axis) Segment {
        const o = self.options;
        const horizontal = o.orientation == .top or o.orientation == .bottom;
        return .{ .start = if (horizontal) .{ .x = o.scale.range.start, .y = o.origin } else .{ .x = o.origin, .y = o.scale.range.start }, .end = if (horizontal) .{ .x = o.scale.range.end, .y = o.origin } else .{ .x = o.origin, .y = o.scale.range.end } };
    }
    pub fn tick(self: Axis, value: f64) Error!Tick {
        const o = (try init(self.options)).options;
        const position = try o.scale.map(value);
        const horizontal = o.orientation == .top or o.orientation == .bottom;
        const sign: f128 = if (o.orientation == .top or o.orientation == .left) -1 else 1;
        const end = try narrow(@as(f128, o.origin) + sign * @as(f128, o.tick_size));
        const label = try narrow(@as(f128, o.origin) + sign * (@as(f128, o.tick_size) + @as(f128, o.label_gap)));
        const grid = try narrow(@as(f128, o.origin) - sign * @as(f128, o.grid_length));
        const start: Point = if (horizontal) .{ .x = position, .y = o.origin } else .{ .x = o.origin, .y = position };
        return .{ .value = value, .position = position, .mark = .{ .start = start, .end = if (horizontal) .{ .x = position, .y = end } else .{ .x = end, .y = position } }, .grid = .{ .start = start, .end = if (horizontal) .{ .x = position, .y = grid } else .{ .x = grid, .y = position } }, .label = if (horizontal) .{ .x = position, .y = label } else .{ .x = label, .y = position }, .anchor = if (horizontal) .middle else if (o.orientation == .left) .end else .start, .baseline = if (!horizontal) .middle else if (o.orientation == .bottom) .hanging else .auto };
    }
    pub fn writeTicks(self: Axis, input: struct { values: []const f64, output: []Tick }) Error![]const Tick {
        if (input.values.len > max_ticks or input.output.len < input.values.len) return error.CapacityExceeded;
        var result: [max_ticks]Tick = undefined;
        for (input.values, 0..) |value, i| result[i] = try self.tick(value);
        @memcpy(input.output[0..input.values.len], result[0..input.values.len]);
        return input.output[0..input.values.len];
    }
};

fn validateRect(rect: Rect) Error!void {
    try finite(&.{ rect.x, rect.y, rect.width, rect.height });
    if (rect.width < 0 or rect.height < 0) return error.InvalidGeometry;
    _ = try narrow(@as(f128, rect.x) + @as(f128, rect.width));
    _ = try narrow(@as(f128, rect.y) + @as(f128, rect.height));
}
fn inside(point: Point, rect: Rect) bool {
    return point.x >= rect.x and point.y >= rect.y and point.x <= rect.x + rect.width and point.y <= rect.y + rect.height;
}
// Liang-Barsky segment clipping also retains entry/exit points across the plot.
fn clipSegment(segment: Segment, rect: Rect) Error!?Segment {
    var lo: f128 = 0;
    var hi: f128 = 1;
    const dx = @as(f128, segment.end.x) - @as(f128, segment.start.x);
    const dy = @as(f128, segment.end.y) - @as(f128, segment.start.y);
    const ps = [_]f128{ -dx, dx, -dy, dy };
    const qs = [_]f128{ @as(f128, segment.start.x) - @as(f128, rect.x), @as(f128, rect.x) + @as(f128, rect.width) - @as(f128, segment.start.x), @as(f128, segment.start.y) - @as(f128, rect.y), @as(f128, rect.y) + @as(f128, rect.height) - @as(f128, segment.start.y) };
    for (ps, qs) |p, q| {
        if (p == 0) {
            if (q < 0) return null;
        } else {
            const ratio = q / p;
            if (p < 0) lo = @max(lo, ratio) else hi = @min(hi, ratio);
            if (lo > hi) return null;
        }
    }
    return .{ .start = .{ .x = try narrow(@as(f128, segment.start.x) + lo * dx), .y = try narrow(@as(f128, segment.start.y) + lo * dy) }, .end = .{ .x = try narrow(@as(f128, segment.start.x) + hi * dx), .y = try narrow(@as(f128, segment.start.y) + hi * dy) } };
}
pub const LineOptions = struct { points: []const ?Point, x_scale: Linear, y_scale: Linear, buffer: []u8, clip: ?Rect = null };
const Path = struct {
    output: ?[]u8,
    len: usize = 0,
    fn add(self: *Path, command: u8, point: Point) Error!void {
        var scratch: [768]u8 = undefined;
        const text = std.fmt.bufPrint(&scratch, "{c}{d},{d}", .{ command, if (point.x == 0) @as(f64, 0) else point.x, if (point.y == 0) @as(f64, 0) else point.y }) catch return error.CapacityExceeded;
        const end = std.math.add(usize, self.len, text.len) catch return error.Overflow;
        if (self.output) |out| @memcpy(out[self.len..end], text);
        self.len = end;
    }
};
fn pathPass(input: LineOptions, output: ?[]u8) Error!usize {
    var writer = Path{ .output = output };
    var previous: ?Point = null;
    var pen: ?Point = null;
    for (input.points) |item| {
        const raw = item orelse {
            previous = null;
            pen = null;
            continue;
        };
        const point = Point{ .x = try input.x_scale.map(raw.x), .y = try input.y_scale.map(raw.y) };
        if (previous) |old| {
            const segment = if (input.clip) |rect| try clipSegment(.{ .start = old, .end = point }, rect) else Segment{ .start = old, .end = point };
            if (segment) |visible| {
                if (pen == null or pen.?.x != visible.start.x or pen.?.y != visible.start.y) try writer.add('M', visible.start);
                try writer.add('L', visible.end);
                pen = visible.end;
            } else pen = null;
        } else if (input.clip == null or inside(point, input.clip.?)) {
            try writer.add('M', point);
            pen = point;
        }
        previous = point;
    }
    return writer.len;
}
/// Null points break segments. An empty series returns ""; one point yields M.
/// Optional geometric clipping preserves crossing segments. SVG clipping may
/// additionally contain strokes. Buffer must not overlap the immutable inputs.
pub fn linePath(input: LineOptions) Error![]const u8 {
    _ = try Linear.init(.{ .domain = input.x_scale.domain, .range = input.x_scale.range, .clamp = input.x_scale.clamp });
    _ = try Linear.init(.{ .domain = input.y_scale.domain, .range = input.y_scale.range, .clamp = input.y_scale.clamp });
    if (input.clip) |rect| try validateRect(rect);
    const len = try pathPass(input, null);
    if (len > input.buffer.len) return error.CapacityExceeded;
    _ = try pathPass(input, input.buffer);
    return input.buffer[0..len];
}

pub const BarDatum = struct { key: u32, category: usize, value: ?f64 };
pub const Bar = struct { key: u32, value: f64, rect: Rect };
pub const BarOptions = struct { data: []const BarDatum, categories: Band, values: Linear, baseline: f64 = 0, orientation: enum { vertical, horizontal } = .vertical, clip: ?Rect = null, output: []Bar };
fn barRect(input: BarOptions, datum: BarDatum) Error!Rect {
    const category = try input.categories.at(datum.category);
    const zero = try input.values.map(input.baseline);
    const value = try input.values.map(datum.value.?);
    const start = @min(zero, value);
    const size = try narrow(@abs(@as(f128, zero) - @as(f128, value)));
    var rect = if (input.orientation == .vertical) Rect{ .x = category.start, .y = start, .width = category.width, .height = size } else Rect{ .x = start, .y = category.start, .width = size, .height = category.width };
    if (input.clip) |clip| {
        const x = std.math.clamp(rect.x, clip.x, clip.x + clip.width);
        const y = std.math.clamp(rect.y, clip.y, clip.y + clip.height);
        const right = std.math.clamp(try narrow(@as(f128, rect.x) + @as(f128, rect.width)), clip.x, clip.x + clip.width);
        const bottom = std.math.clamp(try narrow(@as(f128, rect.y) + @as(f128, rect.height)), clip.y, clip.y + clip.height);
        rect = .{ .x = x, .y = y, .width = right - x, .height = bottom - y };
    }
    return rect;
}
/// Null bars are omitted. Non-null zero bars retain their key and zero extent.
/// Caller keys survive reordering; duplicate keys reject the entire output.
pub fn bars(input: BarOptions) Error![]const Bar {
    try finite(&.{input.baseline});
    _ = try Band.init(input.categories.options);
    _ = try Linear.init(.{ .domain = input.values.domain, .range = input.values.range, .clamp = input.values.clamp });
    if (input.clip) |clip| try validateRect(clip);
    var count: usize = 0;
    for (input.data, 0..) |datum, i| {
        if (datum.category >= input.categories.options.count) return error.IndexOutOfBounds;
        for (input.data[0..i]) |other| if (other.key == datum.key) return error.DuplicateKey;
        if (datum.value == null) continue;
        _ = try barRect(input, datum);
        count += 1;
    }
    if (count > input.output.len) return error.CapacityExceeded;
    count = 0;
    for (input.data) |datum| {
        if (datum.value == null) continue;
        input.output[count] = .{ .key = datum.key, .value = datum.value.?, .rect = try barRect(input, datum) };
        count += 1;
    }
    return input.output[0..count];
}

test {
    _ = @import("charts_test.zig");
}
