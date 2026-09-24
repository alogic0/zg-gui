//! State and view values for the HTML-template demo. No runtime parser.
const std = @import("std");
const gui = @import("zg_gui");
const template = @import("demo_template").Scoped(.{ .first = 1, .count = 999 });
const panels = @import("controls_template").Scoped(.{ .first = 1000, .count = 3000 });
comptime {
    gui.template.validateNamespaces(&.{ .{ .first = 1, .count = 999 }, .{ .first = 1000, .count = 3000 } });
}
const P = gui.Projection(template.snapshot_capacity + panels.snapshot_capacity);
const Row = struct { id: u32, label: []const u8, input_label: []const u8 };
const InputKind = enum(u32) { name = 1, theme = 2, channel = 3, secondary_channel = 4 };
const State = struct {
    count: u32 = 0,
    email: bool = true,
    secondary_email: bool = true,
    dark: bool = false,
    details: bool = false,
    reversed: bool = false,
    extra: bool = false,
    hide_email: bool = false,
    name: [128]u8 = undefined,
    name_len: usize = 0,
};

var state = State{};
var snapshot = P.Snapshot{};
var exchange: [128]u8 = undefined;
// Admit the formatted template, generated IDs, all three rows and the full
// 128-byte draft plus two independent panels; native tests exercise full resync.
var scratch: [16384]u8 = undefined;
var output: [16384]u8 = undefined;
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
    if (s.reversed) std.mem.reverse(Row, rows[0..if (s.extra) @as(usize, 3) else 2]);
    template.project(&p, .{
        .panels = PanelSlot{ .state = s },
        .name = s.name[0..s.name_len],
        .greeting = if (s.name_len == 0) "friend" else s.name[0..s.name_len],
        .theme = @as([]const u8, if (s.dark) "dark" else "light"),
        .theme_label = @as([]const u8, if (s.dark) "Light theme" else "Dark theme"),
        .details = s.details,
        .count = s.count,
        .email_action_label = @as([]const u8, if (s.hide_email) "Restore Email option" else "Remove Email option"),
        .rows = rows[0..if (s.extra) @as(usize, 3) else 2],
        .actions = .{ .increment = Action.increment, .details = Action.details, .reverse = Action.reverse, .extra = Action.extra, .decrement = Action.decrement, .reset = Action.reset, .theme = Action.theme, .email_option = Action.email_option },
        .inputs = .{ .name = InputKind.name },
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

const PanelSlot = struct {
    state: *const State,
    pub fn project(slot: PanelSlot, p: anytype, owner: struct { node: u32 }) void {
        _ = owner; // These two panels have fixed membership.
        const s = slot.state;
        var rows = [_]Row{
            .{ .id = 1, .label = "First row", .input_label = "First row draft" },
            .{ .id = 2, .label = "Second row", .input_label = "Second row draft" },
            .{ .id = 3, .label = "Third row", .input_label = "Third row draft" },
        };
        if (s.reversed) std.mem.reverse(Row, rows[0..if (s.extra) @as(usize, 3) else 2]);
        const Option = struct { id: u32, value: []const u8, label: []const u8 };
        const options = [_]Option{ .{ .id = 1, .value = "sms", .label = "SMS" }, .{ .id = 2, .value = "email", .label = "Email" } };
        const Marker = struct { id: u32, x: u32 };
        const markers = [_]Marker{ .{ .id = 1, .x = 8 }, .{ .id = 2, .x = 20 }, .{ .id = 3, .x = 32 } };
        const shared: struct {
            title: []const u8,
            control_id: []const u8,
            selected: []const u8,
            selection_label: []const u8,
            unavailable: bool,
            icon: []const u8,
            inputs: struct { channel: InputKind },
            options: []const Option,
            rows: []const Row,
            markers: []const Marker,
        } = .{
            .title = @as([]const u8, "Primary integration"),
            .control_id = @as([]const u8, "primary-channel"),
            .selected = @as([]const u8, if (s.email) "email" else "sms"),
            .selection_label = @as([]const u8, if (s.email and s.hide_email) "Email — temporarily unavailable" else if (s.email) "Email" else "SMS"),
            .unavailable = s.email and s.hide_email,
            .icon = @as([]const u8, if (s.dark) "icons.svg#link-active" else "icons.svg#link"),
            .inputs = .{ .channel = InputKind.channel },
            .options = options[0..if (s.hide_email) @as(usize, 1) else 2],
            .rows = rows[0..if (s.extra) @as(usize, 3) else 2],
            .markers = markers[0..if (s.extra) @as(usize, 3) else 2],
        };
        var other = shared;
        other.title = "Secondary integration";
        other.control_id = "secondary-channel";
        other.selected = if (s.secondary_email) "email" else "sms";
        other.selection_label = if (s.secondary_email and s.hide_email) "Email — temporarily unavailable" else if (s.secondary_email) "Email" else "SMS";
        other.unavailable = s.secondary_email and s.hide_email;
        other.inputs.channel = .secondary_channel;
        @import("controls_template").projectAt(p, .{ .primary = shared, .secondary = other }, .{ .first = 1000, .count = 3000 });
    }
};

pub export fn init() u32 {
    return render(.{ .next_state = .{}, .mode = .full });
}
pub export fn resync() u32 {
    return render(.{ .next_state = state, .mode = .full });
}
const Action = enum(u32) { increment = 1, details = 2, reverse = 3, extra = 4, decrement, reset, theme, email_option };
fn update(input: struct { action: u32, value: i32 }) u32 {
    _ = input.value;
    var next = state;
    const action = std.enums.fromInt(Action, input.action) orelse return render(.{ .next_state = next, .mode = .patch });
    switch (action) {
        .increment => next.count +|= 1,
        .decrement => next.count -|= 1,
        .reset => next.count = 0,
        .theme => next.dark = !next.dark,
        .email_option => next.hide_email = !next.hide_email,
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
            .channel => {
                if (std.mem.eql(u8, value, "email")) next.email = true;
                if (std.mem.eql(u8, value, "sms")) next.email = false;
            },
            .secondary_channel => {
                if (std.mem.eql(u8, value, "email")) next.secondary_email = true;
                if (std.mem.eql(u8, value, "sms")) next.secondary_email = false;
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

test "counter bounds and reset preserve unrelated state with leaf patches" {
    _ = init();
    try std.testing.expectEqual(@as(u32, 0), dispatch(@backingInt(Action.decrement), 0));
    _ = render(.{ .next_state = .{ .count = std.math.maxInt(u32), .dark = true, .details = true, .reversed = true }, .mode = .full });
    try std.testing.expectEqual(@as(u32, 0), dispatch(@backingInt(Action.increment), 0));
    _ = dispatch(@backingInt(Action.decrement), 0);
    try std.testing.expectEqual(std.math.maxInt(u32) - 1, state.count);
    _ = dispatch(@backingInt(Action.reset), 0);
    try std.testing.expectEqual(@as(u32, 0), state.count);
    try std.testing.expect(state.dark and state.details and state.reversed);
    var expected: [64]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "T\t{d}\t\"0\"\n", .{template.nodes.count}), output[0..output_len]);
    try std.testing.expectEqual(@as(u32, 0), dispatch(@backingInt(Action.reset), 0));
    try std.testing.expect(resync() > 0);
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
    _ = dispatch(@backingInt(Action.email_option), 0);
    try std.testing.expect(resync() > 0);
    try std.testing.expectEqual(gui.patch.RenderMode.full, render_mode);
    try std.testing.expectEqual(@as(usize, 128), state.name_len);
}

test "component select updates only its instance without replacing either panel" {
    _ = init();
    @memcpy(exchange[0..3], "sms");
    _ = setInput(3, 3);
    const stream = output[0..output_len];
    try std.testing.expect(std.mem.indexOf(u8, stream, "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, stream, "J\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, stream, std.fmt.comptimePrint("T\t{d}\t\"SMS\"\n", .{panels.nodes.@"primary.selection"})) != null);
    var expected: [128]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, stream, try std.fmt.bufPrint(&expected, "V\t{d}\t\"sms\"", .{panels.nodes.@"primary.channel"})) != null);
    try std.testing.expect(std.mem.indexOf(u8, stream, try std.fmt.bufPrint(&expected, "V\t{d}\t", .{panels.nodes.@"secondary.channel"})) == null);
}
