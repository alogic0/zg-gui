//! State and view values for the HTML-template demo. No runtime parser.
const std = @import("std");
const gui = @import("zg_gui");
const template = @import("demo_template");
const P = gui.Projection(template.snapshot_capacity);
const Row = struct { id: u32, label: []const u8, input_label: []const u8 };
const InputKind = enum(u32) { name = 1, theme = 2 };
const State = struct {
    count: u32 = 0,
    dark: bool = false,
    details: bool = false,
    reversed: bool = false,
    extra: bool = false,
    name: [128]u8 = undefined,
    name_len: usize = 0,
};

var state = State{};
var snapshot = P.Snapshot{};
var exchange: [128]u8 = undefined;
// Admit the formatted template, generated IDs, all three rows and the full
// 128-byte draft after HTML escaping; native tests exercise that full resync.
var scratch: [8192]u8 = undefined;
var output: [8192]u8 = undefined;
var output_len: usize = 0;
var render_mode: gui.patch.RenderMode = .full;

// Publish state and snapshot only after BOTH bounded writers succeed.
fn render(input: struct { next_state: State, mode: gui.patch.RenderMode }) u32 {
    var next_snapshot = P.Snapshot{};
    var html = gui.html.Writer{ .buffer = &scratch };
    var stream = gui.html.Writer{ .buffer = &output };
    var patches = gui.patch.Writer{ .output = &stream };
    var p = P{
        .html = &html,
        .patches = if (input.mode == .patch) &patches else null,
        .previous = if (input.mode == .patch) &snapshot else null,
        .next = &next_snapshot,
        .writing = input.mode == .full,
    };
    const s = &input.next_state;
    var rows = [_]Row{
        .{ .id = 1, .label = "First row", .input_label = "First row draft" },
        .{ .id = 2, .label = "Second row", .input_label = "Second row draft" },
        .{ .id = 3, .label = "Third row", .input_label = "Third row draft" },
    };
    if (s.reversed) std.mem.swap(Row, &rows[0], &rows[1]);
    template.project(&p, .{
        .name = s.name[0..s.name_len],
        .greeting = if (s.name_len == 0) "friend" else s.name[0..s.name_len],
        .theme = @as([]const u8, if (s.dark) "dark" else "light"),
        .dark = s.dark,
        .details = s.details,
        .count = s.count,
        .rows = rows[0..if (s.extra) @as(usize, 3) else 2],
        .actions = .{ .increment = Action.increment, .details = Action.details, .reverse = Action.reverse, .extra = Action.extra },
        .inputs = .{ .name = InputKind.name, .theme = InputKind.theme },
    });
    if (html.failed or stream.failed) {
        // No partial stream, candidate state or snapshot is published.
        output_len = 0;
        render_mode = .patch;
        return 0;
    }
    if (input.mode == .full) {
        @memcpy(output[0..html.len], html.slice());
        output_len = html.len;
    } else output_len = stream.len;
    state = input.next_state;
    snapshot = next_snapshot;
    render_mode = input.mode;
    return @intCast(output_len);
}

pub export fn init() u32 {
    return render(.{ .next_state = .{}, .mode = .full });
}
pub export fn resync() u32 {
    return render(.{ .next_state = state, .mode = .full });
}
const Action = enum(u32) { increment = 1, details = 2, reverse = 3, extra = 4 };
fn update(input: struct { action: u32, value: i32 }) u32 {
    _ = input.value;
    var next = state;
    const action = std.enums.fromInt(Action, input.action) orelse return render(.{ .next_state = next, .mode = .patch });
    switch (action) {
        .increment => next.count +|= 1,
        .details => next.details = !next.details,
        .reverse => next.reversed = !next.reversed,
        .extra => next.extra = !next.extra,
    }
    return render(.{ .next_state = next, .mode = .patch });
}
pub export fn dispatch(action: u32, value: i32) u32 {
    return update(.{ .action = action, .value = value });
}
fn acceptInput(input: struct { kind: u32, length: u32 }) u32 {
    var next = state;
    if (input.length <= exchange.len) {
        const value = exchange[0..input.length];
        const kind = std.enums.fromInt(InputKind, input.kind) orelse return render(.{ .next_state = next, .mode = .patch });
        switch (kind) {
            .name => if (std.unicode.utf8ValidateSlice(value)) {
                @memcpy(next.name[0..value.len], value);
                next.name_len = value.len;
            },
            .theme => {
                if (std.mem.eql(u8, value, "true")) next.dark = true;
                if (std.mem.eql(u8, value, "false")) next.dark = false;
            },
        }
    }
    return render(.{ .next_state = next, .mode = .patch });
}
pub export fn setInput(kind: u32, length: u32) u32 {
    return acceptInput(.{ .kind = kind, .length = length });
}
pub export fn getRenderBuffer() usize {
    return @intFromPtr(&output);
}
pub export fn getRenderLength() u32 {
    return @intCast(output_len);
}
pub export fn getRenderMode() u32 {
    return @backingInt(render_mode);
}
pub export fn getExchangeBuffer() usize {
    return @intFromPtr(&exchange);
}
pub export fn getExchangeCapacity() u32 {
    return exchange.len;
}

test "counter and disclosure changes never replace their ancestor" {
    _ = init();
    _ = dispatch(1, 0);
    var expected: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "T\t{d}\t\"1\"\n", .{template.nodes.count}), output[0..output_len]);
    _ = dispatch(2, 0);
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "A\t{d}\taria-expanded\ttrue\nR\t{d}\thidden\n", .{ template.nodes.details_trigger, template.nodes.details }), output[0..output_len]);
}

test "input admission preserves state on overflow and invalid UTF-8" {
    _ = init();
    exchange[0] = 'a';
    _ = setInput(1, 1);
    _ = setInput(1, 129);
    try std.testing.expectEqualStrings("a", state.name[0..state.name_len]);
    exchange[0] = 0xff;
    _ = setInput(1, 1);
    try std.testing.expectEqualStrings("a", state.name[0..state.name_len]);
}

test "maximum admitted escaped input also fits a full recovery projection" {
    _ = init();
    @memset(&exchange, '"');
    _ = setInput(1, exchange.len);
    _ = dispatch(4, 0);
    try std.testing.expect(resync() > 0);
    try std.testing.expectEqual(gui.patch.RenderMode.full, render_mode);
    try std.testing.expectEqual(@as(usize, 128), state.name_len);
}
