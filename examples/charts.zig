//! Numerical values stay in Zig; the browser only mounts SVG and reports width.
const std = @import("std");
const gui = @import("zg_gui");
const c = gui.charts;
const template = @import("charts_template").Scoped(.{ .first = 1, .count = 20000 });
const P = gui.Projection(template.snapshot_capacity);
const Action = enum(u32) { apply = 1, reset = 2, reverse = 3, empty = 4 };
const Input = enum(u32) { values = 1, width = 2 };
const sample = "12, 28, , -8, 45, 24, 62, 38";
const State = struct {
    draft: [256]u8 = undefined,
    draft_len: usize = 0,
    values: [8]?f64 = @splat(null),
    count: usize = 0,
    reversed: bool = false,
    width: u32 = 560,
    invalid: bool = false,
    fn set(self: *State, value: []const u8) void {
        @memcpy(self.draft[0..value.len], value);
        self.draft_len = value.len;
    }
    fn parse(self: *State) !void {
        var values: [8]?f64 = @splat(null);
        var count: usize = 0;
        const source = std.mem.trim(u8, self.draft[0..self.draft_len], " \t\r\n");
        if (source.len != 0) {
            var parts = std.mem.splitScalar(u8, source, ',');
            while (parts.next()) |part| {
                if (count == values.len) return error.InvalidData;
                const text = std.mem.trim(u8, part, " \t\r\n");
                if (text.len != 0) {
                    const value = std.fmt.parseFloat(f64, text) catch return error.InvalidData;
                    if (!std.math.isFinite(value) or @abs(value) > 1000) return error.InvalidData;
                    values[count] = value;
                }
                count += 1;
            }
        }
        self.values = values;
        self.count = count;
        self.invalid = false;
    }
};
const Tick = struct { id: u32, label: []const u8, mark: SvgSegment, grid: SvgSegment, label_point: SvgPoint, anchor: []const u8, baseline: []const u8 };
const Bar = struct { id: u32, rect: SvgRect };
const Dot = struct { id: u32, point: SvgPoint };
const Row = struct { id: u32, value: []const u8 };
const Plot = struct { view_box: []const u8, description: []const u8, kind: []const u8, clip_id: []const u8, plot_width: []const u8, right: []const u8, middle: []const u8, zero: []const u8, x_ticks: []const Tick, y_ticks: []const Tick, path: []const u8, bars: []const Bar, points: []const Dot };
var state: State = .{};
var snapshot: P.Snapshot = .{};
var scratch: [32768]u8 = undefined;
var output: [32768]u8 = undefined;
var exchange: [256]u8 = undefined;
var output_len: usize = 0;
var mode: gui.patch.RenderMode = .full;
const SvgPoint = struct { x: []const u8, y: []const u8 };
const SvgSegment = struct { start: SvgPoint, end: SvgPoint };
const SvgRect = struct { x: []const u8, y: []const u8, width: []const u8, height: []const u8 };
const Numbers = struct {
    storage: [256][32]u8 = undefined,
    len: usize = 0,
    fn value(self: *Numbers, v: f64) ![]const u8 {
        if (self.len == self.storage.len) return error.NumberCapacity;
        const result = try std.fmt.bufPrint(&self.storage[self.len], "{d:.2}", .{if (@abs(v) < 0.005) @as(f64, 0) else v});
        self.len += 1;
        return result;
    }
    fn point(self: *Numbers, v: c.Point) !SvgPoint {
        return .{ .x = try self.value(v.x), .y = try self.value(v.y) };
    }
    fn segment(self: *Numbers, v: c.Segment) !SvgSegment {
        return .{ .start = try self.point(v.start), .end = try self.point(v.end) };
    }
    fn rect(self: *Numbers, v: c.Rect) !SvgRect {
        return .{ .x = try self.value(v.x), .y = try self.value(v.y), .width = try self.value(v.width), .height = try self.value(v.height) };
    }
};
fn tickView(numbers: *Numbers, id: u32, tick: c.Axis.Tick, label: []const u8) !Tick {
    return .{ .id = id, .label = label, .mark = try numbers.segment(tick.mark), .grid = try numbers.segment(tick.grid), .label_point = try numbers.point(tick.label), .anchor = @tagName(tick.anchor), .baseline = @tagName(tick.baseline) };
}
fn render(s: State, next_mode: gui.patch.RenderMode) !u32 {
    var numbers = Numbers{};
    const width: f64 = @floatFromInt(s.width);
    const plot = c.Rect{ .x = 48, .y = 24, .width = width - 64, .height = 248 };
    const band = try c.Band.init(.{ .count = 8, .range = if (s.reversed) .{ .start = width - 16, .end = 48 } else .{ .start = 48, .end = width - 16 }, .inner_padding = 0.35, .outer_padding = 0.2 });
    const x = try c.Linear.init(.{ .domain = .{ .start = 1, .end = 8 }, .range = .{ .start = (try band.at(0)).center, .end = (try band.at(7)).center } });
    const y = try c.Linear.init(.{ .domain = .{ .start = -20, .end = 80 }, .range = .{ .start = 272, .end = 24 } });
    const y_axis = try c.Axis.init(.{ .scale = y, .orientation = .left, .origin = 48, .grid_length = plot.width });
    const x_axis = try c.Axis.init(.{ .scale = x, .orientation = .bottom, .origin = 272 });
    var y_values: [16]f64 = undefined;
    const yt = try c.ticks(.{ .domain = y.domain, .output = &y_values });
    var y_ticks: [16]Tick = undefined;
    var x_ticks: [8]Tick = undefined;
    var labels: [24][32]u8 = undefined;
    for (yt.values, 0..) |v, i| y_ticks[i] = try tickView(&numbers, @intCast(i + 1), try y_axis.tick(v), try c.formatTick(.{ .value = v, .step = yt.step, .buffer = &labels[i] }));
    for (&x_ticks, 0..) |*tick, ordinal| {
        const i = if (s.reversed) 7 - ordinal else ordinal;
        const v: f64 = @floatFromInt(i + 1);
        tick.* = try tickView(&numbers, @intCast(i + 1), try x_axis.tick(v), try c.formatTick(.{ .value = v, .step = 1, .buffer = &labels[16 + i] }));
    }
    var points: [8]?c.Point = @splat(null);
    for (s.values[0..s.count], 0..) |value, i| if (value) |v| {
        points[i] = .{ .x = @floatFromInt(i + 1), .y = v };
    };
    var path_memory: [4096]u8 = undefined;
    const path = try c.linePath(.{ .points = points[0..s.count], .x_scale = x, .y_scale = y, .clip = plot, .buffer = &path_memory });
    var data: [8]c.BarDatum = undefined;
    var rows: [8]Row = undefined;
    var row_labels: [8][32]u8 = undefined;
    var dots: [8]Dot = undefined;
    var dot_count: usize = 0;
    for (0..s.count) |ordinal| {
        const i = if (s.reversed) s.count - 1 - ordinal else ordinal;
        const id: u32 = @intCast(i + 1);
        data[ordinal] = .{ .key = id, .category = i, .value = s.values[i] };
        rows[ordinal] = .{ .id = id, .value = if (s.values[i]) |v| try c.formatTick(.{ .value = v, .step = 1, .buffer = &row_labels[ordinal] }) else "Missing" };
        if (s.values[i]) |v| {
            dots[dot_count] = .{ .id = id, .point = try numbers.point(.{ .x = try x.map(@floatFromInt(id)), .y = try y.map(v) }) };
            dot_count += 1;
        }
    }
    var bar_geometry: [8]c.Bar = undefined;
    const geometry = try c.bars(.{ .data = data[0..s.count], .categories = band, .values = y, .clip = plot, .output = &bar_geometry });
    var bars: [8]Bar = undefined;
    for (geometry, 0..) |b, i| bars[i] = .{ .id = b.key, .rect = try numbers.rect(b.rect) };
    var dimensions: [64]u8 = undefined;
    const view = Plot{ .view_box = try std.fmt.bufPrint(&dimensions, "0 0 {d} 330", .{s.width}), .description = "Line chart of the values in the table below. Scale minus 20 to 80; values outside it are clipped. Missing values leave gaps.", .kind = "line", .clip_id = "line-plot", .plot_width = try numbers.value(plot.width), .right = try numbers.value(width - 16), .middle = try numbers.value(width / 2), .zero = try numbers.value(try y.map(0)), .x_ticks = &x_ticks, .y_ticks = y_ticks[0..yt.values.len], .path = path, .bars = &.{}, .points = dots[0..dot_count] };
    var bar = view;
    bar.description = "Bar chart of the values in the table below. Bars share zero. Scale minus 20 to 80; values outside it are clipped.";
    bar.kind = "bar";
    bar.clip_id = "bar-plot";
    bar.path = "";
    bar.points = &.{};
    bar.bars = bars[0..geometry.len];
    var next = P.Snapshot{};
    var html = gui.html.Writer{ .buffer = &scratch };
    var out = gui.html.Writer{ .buffer = &output };
    var patches = gui.patch.Writer{ .output = &out };
    var p = P{ .html = &html, .patches = if (next_mode == .patch) &patches else null, .previous = if (next_mode == .patch) &snapshot else null, .next = &next, .writing = next_mode == .full };
    template.project(&p, .{ .line = view, .bar = bar, .rows = rows[0..s.count], .draft = s.draft[0..s.draft_len], .invalid = s.invalid, .error_message = if (s.invalid) @as([]const u8, "Use up to eight finite numbers from −1,000 to 1,000, separated by commas. Your last accepted charts remain visible.") else "", .empty = geometry.len == 0, .reversed = s.reversed, .input = Input.values, .actions = .{ .apply = Action.apply, .reset = Action.reset, .reverse = Action.reverse, .empty = Action.empty } });
    if (html.failed or out.failed) return error.OutputOverflow;
    if (next_mode == .full) {
        @memcpy(output[0..html.len], html.slice());
        output_len = html.len;
    } else output_len = out.len;
    snapshot = next;
    state = s;
    mode = next_mode;
    return @intCast(output_len);
}
fn publish(s: State, next_mode: gui.patch.RenderMode) u32 {
    return render(s, next_mode) catch {
        output_len = 0;
        mode = .patch;
        return 0;
    };
}
pub export fn init() u32 {
    var s = State{};
    s.set(sample);
    s.parse() catch unreachable;
    snapshot = .{};
    return publish(s, .full);
}
pub export fn resync() u32 {
    return publish(state, .full);
}
pub export fn dispatch(raw: u32, _: i32) u32 {
    const action = std.enums.fromInt(Action, raw) orelse return 0;
    var s = state;
    switch (action) {
        .apply => s.parse() catch {
            s.invalid = true;
        },
        .reset => {
            s.set(sample);
            s.reversed = false;
            s.parse() catch unreachable;
        },
        .reverse => s.reversed = !s.reversed,
        .empty => {
            s.set("");
            s.parse() catch unreachable;
        },
    }
    return publish(s, .patch);
}
pub export fn setInput(raw: u32, length: u32) u32 {
    const kind = std.enums.fromInt(Input, raw) orelse return 0;
    if (length > exchange.len or !std.unicode.utf8ValidateSlice(exchange[0..length])) return 0;
    var s = state;
    switch (kind) {
        .values => s.set(exchange[0..length]),
        .width => {
            const width = std.fmt.parseInt(u32, exchange[0..length], 10) catch return 0;
            if (width < 320 or width > 720) return 0;
            s.width = width;
        },
    }
    return publish(s, .patch);
}
pub export fn getRenderBuffer() usize {
    return @intFromPtr(&output);
}
pub export fn getRenderLength() u32 {
    return @intCast(output_len);
}
pub export fn getRenderMode() u32 {
    return @backingInt(mode);
}
pub export fn getExchangeBuffer() usize {
    return @intFromPtr(&exchange);
}
pub export fn getExchangeCapacity() u32 {
    return exchange.len;
}

fn edit(value: []const u8) void {
    @memcpy(exchange[0..value.len], value);
    _ = setInput(@backingInt(Input.values), @intCast(value.len));
}
test "numerical chart example retains accepted data through invalid drafts and recovers" {
    try std.testing.expect(init() > 0);
    const accepted = state.values;
    edit("12, NaN, 28");
    try std.testing.expect(dispatch(@backingInt(Action.apply), 0) > 0);
    try std.testing.expect(state.invalid);
    try std.testing.expectEqualDeep(accepted, state.values);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "J\t") == null);
    edit("0, -20, , 80");
    _ = dispatch(@backingInt(Action.apply), 0);
    try std.testing.expect(!state.invalid and state.count == 4);
    try std.testing.expectEqual(@as(?f64, -20), state.values[1]);
    try std.testing.expectEqual(@as(?f64, null), state.values[2]);
    _ = dispatch(@backingInt(Action.empty), 0);
    try std.testing.expect(state.count == 0);
    try std.testing.expect(resync() > 0);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "No values to plot") != null);
}
test "numerical chart example admits maximum escaped drafts clipped values and narrow resync" {
    _ = init();
    @memset(&exchange, '<');
    _ = setInput(@backingInt(Input.values), exchange.len);
    _ = dispatch(@backingInt(Action.apply), 0);
    try std.testing.expect(state.invalid and resync() > 0);
    edit("1000, -1000, 0, 0, 80, -20, 1.5, -0.25");
    _ = dispatch(@backingInt(Action.apply), 0);
    try std.testing.expect(!state.invalid);
    @memcpy(exchange[0..3], "320");
    _ = setInput(@backingInt(Input.width), 3);
    _ = dispatch(@backingInt(Action.reverse), 0);
    try std.testing.expect(resync() > 0);
    try std.testing.expectEqual(@as(u32, 320), state.width);
    try std.testing.expect(state.reversed);
    const saved = state;
    @memcpy(exchange[0..3], "100");
    try std.testing.expectEqual(@as(u32, 0), setInput(@backingInt(Input.width), 3));
    try std.testing.expectEqualDeep(saved, state);
}
