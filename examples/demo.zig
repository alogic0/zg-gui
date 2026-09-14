//! A standalone example using only the public framework API.
const std = @import("std");
const gui = @import("zg_gui");
const P = gui.Projection(48);
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
var scratch: [4096]u8 = undefined;
var output: [4096]u8 = undefined;
var output_len: usize = 0;
var render_mode: gui.patch.RenderMode = .full;

fn project(p: *P, s: *const State) void {
    p.add("<main class=\"demo\"");
    p.node(1);
    p.attr(.{ .node = 1, .name = "data-theme", .value = if (s.dark) "dark" else "light" });
    p.add("><header><p class=\"eyebrow\">ZG GUI · ZIG + WEBASSEMBLY</p><h1>Small updates.<br>Steady controls.</h1><p>A standalone application built with the extracted GUI core.</p></header><section class=\"card\"><h2>Your workspace</h2><label for=\"name\">Workspace name</label><input id=\"name\" data-input-kind=\"1\" placeholder=\"Try typing here\"");
    p.node(2);
    p.formValue(.{ .node = 2, .text_value = s.name[0..s.name_len] });
    p.add("><p class=\"preview\">Hello, ");
    p.textElement("span", .{ .node = 3, .value = if (s.name_len == 0) "friend" else s.name[0..s.name_len] });
    p.add(".</p><label class=\"toggle\"><input type=\"checkbox\" data-input-kind=\"2\" data-value-format=\"checked\"");
    p.node(4);
    p.checked(.{ .node = 4, .value = s.dark });
    p.add("> Dark theme</label></section><section class=\"card\"><h2>Keep things in place</h2><div class=\"counter\">");
    var digits: [16]u8 = undefined;
    p.textElement("output", .{ .node = 5, .value = std.fmt.bufPrint(&digits, "{d}", .{s.count}) catch unreachable });
    p.add("<button data-event=\"1\" data-node-id=\"6\">Increment</button></div><button class=\"secondary\" data-event=\"2\" aria-controls=\"details\"");
    p.node(7);
    p.attr(.{ .node = 7, .name = "aria-expanded", .value = if (s.details) "true" else "false" });
    p.add(">Show / hide details</button><p id=\"details\"");
    p.node(8);
    p.visible(.{ .node = 8, .value = s.details });
    p.add(">This paragraph stays mounted when hidden. The counter updates only its own text.</p></section><section class=\"card wide\"><div class=\"section-heading\"><h2>Retained list rows</h2><div class=\"actions\"><button class=\"secondary\" data-event=\"3\">Reverse rows</button><button class=\"secondary\" data-event=\"4\">Toggle third row</button></div></div><ul data-node-id=\"9\">");
    var ids: [3]u32 = if (s.reversed) .{ 11, 10, 12 } else .{ 10, 11, 12 };
    const rows = ids[0..if (s.extra) @as(usize, 3) else 2];
    p.keyedList(.{ .owner = 9, .nodes = rows });
    for (rows) |id| {
        const child = p.beginChild(.{ .owner = 9, .node = id });
        p.add("<li");
        p.node(id);
        p.add("><label>");
        const label: []const u8 = switch (id) {
            10 => "First row",
            11 => "Second row",
            else => "Third row",
        };
        p.escaped(label);
        p.add("<input aria-label=\"");
        p.escaped(label);
        p.add(" draft\" placeholder=\"Unsaved browser draft\"></label></li>");
        p.endChild(child);
    }
    p.order(.{ .owner = 9, .nodes = rows });
    p.add("</ul><p class=\"hint\">Type into a row, then reorder it. Its input and draft stay intact.</p></section><footer>No backend. No UI runtime dependencies. State and updates belong to Zig.</footer></main>");
}

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
    project(&p, &input.next_state);
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
        switch (input.kind) {
            1 => if (std.unicode.utf8ValidateSlice(value)) {
                @memcpy(next.name[0..value.len], value);
                next.name_len = value.len;
            },
            2 => {
                if (std.mem.eql(u8, value, "true")) next.dark = true;
                if (std.mem.eql(u8, value, "false")) next.dark = false;
            },
            else => {},
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
    try std.testing.expectEqualStrings("T\t5\t\"1\"\n", output[0..output_len]);
    _ = dispatch(2, 0);
    try std.testing.expectEqualStrings("A\t7\taria-expanded\ttrue\nR\t8\thidden\n", output[0..output_len]);
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
