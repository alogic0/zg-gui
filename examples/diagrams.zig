//! Bounded source editor and two independently projected drawing scenes.
const std = @import("std");
const gui = @import("zg_gui");
const diagrams = @import("zg_diagrams");
const template = @import("diagrams_template").Scoped(.{ .first = 1, .count = 999 });
const Diagram = diagrams.Diagram(.{ .max_elements = 128, .max_key_bytes = 128 });
const Action = enum(u32) { apply_flow = 1, apply_sequence = 2, reset_flow = 3, reset_sequence = 4 };
const Input = enum(u32) { flow = 1, sequence = 2 };
const P = gui.Projection(template.snapshot_capacity + 2 * Diagram.snapshot_capacity);
const samples = [2][]const u8{
    "flowchart TD\n  Read[Read source] --> Check{Is it ready?}\n  Check -->|Yes| Draw[Draw the result]\n  Check -->|Edit| Read",
    "sequenceDiagram\n  participant Reader\n  participant Engine\n  Reader->>+Engine: Render this source\n  Note over Engine: Arrange the drawing\n  Engine-->>-Reader: Here is your diagram",
};
const descriptions = [2][]const u8{ "Flowchart preview; source text follows", "Sequence preview; source text follows" };
const namespaces = [2]gui.namespace.Range{ .{ .first = 1000, .count = Diagram.node_count }, .{ .first = 10000, .count = Diagram.node_count } };
comptime {
    gui.template.validateNamespaces(&.{ .{ .first = 1, .count = 999 }, .{ .first = namespaces[0].first, .count = namespaces[0].count }, .{ .first = namespaces[1].first, .count = namespaces[1].count } });
}

const Source = struct {
    bytes: [4096]u8 = undefined,
    len: usize = 0,

    fn set(self: *Source, value: []const u8) void {
        @memcpy(self.bytes[0..value.len], value);
        self.len = value.len;
    }
    fn slice(self: *const Source) []const u8 {
        return self.bytes[0..self.len];
    }
};
const State = struct { drafts: [2]Source = .{ .{}, .{} }, accepted: [2]Source = .{ .{}, .{} }, errors: [2][]const u8 = .{ "", "" } };
var state = State{};
var views = [2]Diagram{ .{}, .{} };
var snapshot = P.Snapshot{};
var exchange: [4096]u8 = undefined;
var scene_memory: [512 * 1024]u8 = undefined;
var scratch: [128 * 1024]u8 = undefined;
var output: [128 * 1024]u8 = undefined;
var output_len: usize = 0;
var svg_output: [128 * 1024]u8 = undefined;
var svg_len: usize = 0;
var mode: gui.patch.RenderMode = .full;
var last_error: []const u8 = "";

const Slot = struct {
    view: *Diagram,
    scene: *const diagrams.Scene,
    index: usize,

    pub fn project(self: Slot, p: anytype, _: anytype) void {
        self.view.project(p, .{ .scene = self.scene, .namespace = namespaces[self.index], .description = descriptions[self.index] }) catch |err| {
            last_error = errorMessage(err);
            p.html.failed = true;
        };
    }
};

fn errorMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.EmptyDiagram => "Add at least one node or message, then render again.",
        error.UnsupportedDiagramType => "Start with flowchart, graph, or sequenceDiagram, then render again.",
        error.InvalidSyntax, error.InvalidHeader, error.UnknownParticipant, error.GraphHasCycles => "Check the diagram syntax and participant names, then render again.",
        error.KeyTooLong => "Shorten the node or participant identifiers, then render again.",
        else => "This diagram exceeds the example's drawing limits. Simplify it and render again.",
    };
}

fn scene(allocator: std.mem.Allocator, source: []const u8) !diagrams.Scene {
    return diagrams.engine.buildScene(.{ .allocator = allocator, .source = source, .limits = .{ .max_source_bytes = 4096, .max_nodes = 32, .max_edges = 64, .drawing = .{ .max_elements = 128, .max_data_bytes = 64 * 1024 } } });
}

fn render(next_state: State, next_mode: gui.patch.RenderMode) u32 {
    output_len = 0;
    last_error = "";
    var fixed = std.heap.FixedBufferAllocator.init(&scene_memory);
    var flow = scene(fixed.allocator(), next_state.accepted[0].slice()) catch |err| {
        last_error = errorMessage(err);
        return 0;
    };
    defer flow.deinit();
    var sequence = scene(fixed.allocator(), next_state.accepted[1].slice()) catch |err| {
        last_error = errorMessage(err);
        return 0;
    };
    defer sequence.deinit();
    var next_views = views;
    var next_snapshot = P.Snapshot{};
    var html = gui.html.Writer{ .buffer = &scratch };
    var out = gui.html.Writer{ .buffer = &output };
    var patches = gui.patch.Writer{ .output = &out };
    var p = P{ .html = &html, .next = &next_snapshot, .previous = if (next_mode == .patch) &snapshot else null, .patches = if (next_mode == .patch) &patches else null, .writing = next_mode == .full };
    template.project(&p, .{
        .flow_source = next_state.drafts[0].slice(),
        .sequence_source = next_state.drafts[1].slice(),
        .flow_error = next_state.errors[0],
        .flow_invalid = next_state.errors[0].len != 0,
        .sequence_error = next_state.errors[1],
        .sequence_invalid = next_state.errors[1].len != 0,
        .inputs = .{ .flow = Input.flow, .sequence = Input.sequence },
        .actions = .{ .apply_flow = Action.apply_flow, .apply_sequence = Action.apply_sequence, .reset_flow = Action.reset_flow, .reset_sequence = Action.reset_sequence },
        .flow = Slot{ .view = &next_views[0], .scene = &flow, .index = 0 },
        .sequence = Slot{ .view = &next_views[1], .scene = &sequence, .index = 1 },
    });
    if (html.failed or out.failed) return 0;
    if (next_mode == .full) {
        @memcpy(output[0..html.len], html.slice());
        output_len = html.len;
    } else output_len = out.len;
    snapshot = next_snapshot;
    views = next_views;
    state = next_state;
    mode = next_mode;
    return 1;
}

pub export fn init() u32 {
    state = .{};
    views = .{ .{}, .{} };
    for (samples, 0..) |sample, i| {
        state.drafts[i].set(sample);
        state.accepted[i].set(sample);
    }
    _ = render(state, .full);
    return @intCast(output_len);
}
pub export fn resync() u32 {
    _ = render(state, .full);
    return @intCast(output_len);
}
fn noChange() u32 {
    output_len = 0;
    mode = .patch;
    return 0;
}
pub export fn setInput(kind: u32, length: u32) u32 {
    if (kind < 1 or kind > 2 or length > exchange.len or !std.unicode.utf8ValidateSlice(exchange[0..length])) return noChange();
    var next = state;
    next.drafts[kind - 1].set(exchange[0..length]);
    _ = render(next, .patch);
    return @intCast(output_len);
}
pub export fn dispatch(action: u32, _: i32) u32 {
    if (action < 1 or action > 4) return noChange();
    const index: usize = (action - 1) % 2;
    var next = state;
    if (action >= 3) next.drafts[index].set(samples[index]);
    next.accepted[index] = next.drafts[index];
    next.errors[index] = "";
    if (render(next, .patch) != 0) return @intCast(output_len);
    next.accepted = state.accepted;
    next.errors[index] = if (last_error.len != 0) last_error else "The drawing could not update. Simplify the source and render again.";
    _ = render(next, .patch);
    return @intCast(output_len);
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
pub export fn exportSvg(index: u32) u32 {
    svg_len = 0;
    if (index > 1) return 0;
    var fixed = std.heap.FixedBufferAllocator.init(&scene_memory);
    var drawing = scene(fixed.allocator(), state.accepted[index].slice()) catch return 0;
    defer drawing.deinit();
    const bytes = drawing.renderSvg(fixed.allocator()) catch return 0;
    defer fixed.allocator().free(bytes);
    if (bytes.len > svg_output.len) return 0;
    @memcpy(svg_output[0..bytes.len], bytes);
    svg_len = bytes.len;
    return 1;
}
pub export fn getSvgBuffer() usize {
    return @intFromPtr(&svg_output);
}
pub export fn getSvgLength() u32 {
    return @intCast(svg_len);
}

test "diagram example preserves accepted sources after invalid input and exports both types" {
    try std.testing.expect(init() > 0);
    @memcpy(exchange[0..12], "classDiagram");
    try std.testing.expect(setInput(1, 12) > 0);
    try std.testing.expect(dispatch(1, 0) > 0);
    try std.testing.expectEqualStrings(samples[0], state.accepted[0].slice());
    try std.testing.expect(state.errors[0].len > 0);
    try std.testing.expectEqualStrings(samples[1], state.accepted[1].slice());
    try std.testing.expectEqual(@as(u32, 1), exportSvg(0));
    try std.testing.expect(std.mem.indexOf(u8, svg_output[0..svg_len], "Read source") != null);
    try std.testing.expectEqual(@as(u32, 1), exportSvg(1));
    try std.testing.expect(std.mem.indexOf(u8, svg_output[0..svg_len], "Render this source") != null);
    const source = "graph LR\n A[Changed <&>] --> B[Done]";
    @memcpy(exchange[0..source.len], source);
    try std.testing.expect(setInput(1, source.len) > 0);
    try std.testing.expect(dispatch(1, 0) > 0);
    try std.testing.expectEqualStrings(source, state.accepted[0].slice());
    try std.testing.expectEqual(@as(usize, 0), state.errors[0].len);
    try std.testing.expect(dispatch(3, 0) > 0);
    try std.testing.expectEqualStrings(samples[0], state.accepted[0].slice());
}

test "diagram example rejects malformed exchange and unknown commands without resynchronizing" {
    try std.testing.expect(init() > 0);
    try std.testing.expectEqual(@as(u32, 0), dispatch(999, 0));
    try std.testing.expectEqual(gui.patch.RenderMode.patch, mode);
    try std.testing.expectEqual(@as(u32, 0), setInput(3, 0));
    try std.testing.expectEqual(@as(u32, 0), setInput(1, exchange.len + 1));
    exchange[0] = 0xff;
    try std.testing.expectEqual(@as(u32, 0), setInput(1, 1));
    try std.testing.expectEqualStrings(samples[0], state.accepted[0].slice());
    try std.testing.expectEqual(@as(usize, 0), output_len);
}
