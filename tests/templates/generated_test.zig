const std = @import("std");
const gui = @import("zg_gui");
const view = @import("fixture");
const P = gui.Projection(view.snapshot_capacity);
const Action = enum(u32) { increment = 1 };
const Input = enum(u32) { name = 1, checked = 2 };
const Row = struct { id: u32, label: []const u8 };
const View = struct {
    name: []const u8 = "Ada & <Zig>",
    theme: []const u8 = "light",
    count: u32 = 0,
    checked: bool = false,
    disabled: bool = false,
    show: bool = false,
    title: ?[]const u8 = null,
    rows: []const Row = &.{},
    other_rows: []const Row = &.{},
    actions: struct { increment: Action = .increment } = .{},
    inputs: struct { name: Input = .name, checked: Input = .checked } = .{},
};
const Harness = struct {
    snapshot: P.Snapshot = .{},
    html_bytes: [8192]u8 = undefined,
    patch_bytes: [8192]u8 = undefined,
    fn render(h: *Harness, input: struct { value: View, mode: gui.patch.RenderMode }) ![]const u8 {
        var next = P.Snapshot{};
        var html = gui.html.Writer{ .buffer = &h.html_bytes };
        var output = gui.html.Writer{ .buffer = &h.patch_bytes };
        var patches = gui.patch.Writer{ .output = &output };
        var p = P{
            .html = &html,
            .next = &next,
            .previous = if (input.mode == .patch) &h.snapshot else null,
            .patches = if (input.mode == .patch) &patches else null,
            .writing = input.mode == .full,
        };
        view.project(&p, input.value);
        if (html.failed or output.failed) return error.Rejected;
        h.snapshot = next;
        return if (input.mode == .full) html.slice() else output.slice();
    }
};

test "generated leaf bindings escape HTML and never replace a containing region" {
    var h = Harness{};
    var model = View{};
    const initial = try h.render(.{ .value = model, .mode = .full });
    try std.testing.expect(std.mem.indexOf(u8, initial, "Ada &amp; &lt;Zig&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, initial, "Hello <span") != null);
    model.count = 2;
    const patches = try h.render(.{ .value = model, .mode = .patch });
    var expected: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "T\t{d}\t\"2\"\n", .{view.nodes.count}), patches);
    try std.testing.expectEqualStrings("", try h.render(.{ .value = model, .mode = .patch }));
}

test "generated conditions introduce descendants once and remove only their owner children" {
    var h = Harness{};
    var model = View{};
    _ = try h.render(.{ .value = model, .mode = .full });
    model.show = true;
    const open = try h.render(.{ .value = model, .mode = .patch });
    var prefix: [64]u8 = undefined;
    const html_prefix = try std.fmt.bufPrint(&prefix, "H\t{d}\t", .{view.nodes.conditional});
    try std.testing.expect(std.mem.indexOf(u8, open, html_prefix) != null);
    try std.testing.expect(std.mem.indexOf(u8, open, "T\t") == null);
    model.show = false;
    const closed = try h.render(.{ .value = model, .mode = .patch });
    try std.testing.expect(std.mem.indexOf(u8, closed, html_prefix) != null);
    try std.testing.expect(std.mem.indexOf(u8, closed, "T\t") == null);
}

test "generated property optional attribute and enum event bindings use the typed stream" {
    var h = Harness{};
    var model = View{};
    _ = try h.render(.{ .value = model, .mode = .full });
    model.disabled = true;
    model.checked = true;
    model.name = "\"quoted\"\n🧭";
    model.title = "help";
    const patches = try h.render(.{ .value = model, .mode = .patch });
    try std.testing.expect(std.mem.indexOf(u8, patches, "V\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, patches, "C\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, patches, "\tdisabled\t\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, patches, "\ttitle\thelp\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, patches, "H\t") == null);
    model.title = null;
    model.disabled = false;
    const removed = try h.render(.{ .value = model, .mode = .patch });
    try std.testing.expect(std.mem.indexOf(u8, removed, "\ttitle\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, removed, "\tdisabled\n") != null);
}

test "generated loops retain rows across edits moves and membership changes" {
    var h = Harness{};
    var model = View{ .rows = &.{ .{ .id = 3, .label = "three" }, .{ .id = 5, .label = "five" } }, .other_rows = &.{.{ .id = 3, .label = "another three" }} };
    _ = try h.render(.{ .value = model, .mode = .full });
    model.rows = &.{ .{ .id = 5, .label = "edited" }, .{ .id = 3, .label = "three" } };
    const reordered = try h.render(.{ .value = model, .mode = .patch });
    try std.testing.expect(std.mem.indexOf(u8, reordered, "M\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, reordered, "T\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, reordered, "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, reordered, "D\t") == null);
    model.rows = &.{ .{ .id = 5, .label = "edited" }, .{ .id = 7, .label = "seven" } };
    const changed = try h.render(.{ .value = model, .mode = .patch });
    try std.testing.expect(std.mem.indexOf(u8, changed, "D\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, changed, "J\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, changed, "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, changed, "T\t") == null);
}

test "invalid keys and loop limits reject the candidate snapshot and allow recovery" {
    var h = Harness{};
    var model = View{};
    _ = try h.render(.{ .value = model, .mode = .full });
    const saved_length = h.snapshot.len;
    for ([_][]const Row{
        &.{ .{ .id = 1, .label = "a" }, .{ .id = 1, .label = "b" } },
        &.{ .{ .id = 1, .label = "a" }, .{ .id = 2, .label = "b" }, .{ .id = 3, .label = "c" } },
        &.{.{ .id = std.math.maxInt(u32), .label = "overflow" }},
    }) |rows| {
        model.rows = rows;
        try std.testing.expectError(error.Rejected, h.render(.{ .value = model, .mode = .patch }));
        try std.testing.expectEqual(saved_length, h.snapshot.len);
    }
    model.rows = &.{.{ .id = 1, .label = "accepted" }};
    const accepted = try h.render(.{ .value = model, .mode = .patch });
    try std.testing.expect(std.mem.indexOf(u8, accepted, "J\t") != null);
}

test "independently scoped templates compose leaf and keyed owners without collisions" {
    const left = view.Scoped(.{ .first = 1000, .count = 1000 });
    const right = view.Scoped(.{ .first = 3000, .count = 1000 });
    const Both = gui.Projection(left.snapshot_capacity + right.snapshot_capacity);
    var before = Both.Snapshot{};
    var after = Both.Snapshot{};
    var bytes: [16384]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output_bytes: [8192]u8 = undefined;
    var output = gui.html.Writer{ .buffer = &output_bytes };
    var patches = gui.patch.Writer{ .output = &output };
    var p = Both{ .html = &html, .next = &before };
    const model = View{ .rows = &.{.{ .id = 3, .label = "row" }} };
    left.project(&p, model);
    right.project(&p, model);
    try std.testing.expect(!html.failed);
    for (before.entries[0..before.len], 0..) |entry, i| {
        for (before.entries[0..i]) |other| try std.testing.expect(entry.node != other.node or entry.property != other.property);
    }
    p = .{ .html = &html, .next = &after, .previous = &before, .patches = &patches, .writing = false };
    var changed = model;
    changed.count = 7;
    left.project(&p, changed);
    right.project(&p, model);
    var expected: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "T\t{d}\t\"7\"\n", .{left.nodes.count}), output.slice());
    var too_large = model;
    too_large.rows = &.{.{ .id = 1000, .label = "outside namespace" }};
    html.failed = false;
    after = .{};
    left.project(&p, too_large);
    try std.testing.expect(html.failed);
}
