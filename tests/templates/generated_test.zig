const std = @import("std");
const gui = @import("zg_gui");
const view = @import("fixture");
const P = gui.Projection(view.snapshot_capacity);
const Action = enum(u32) { increment = 1 };
const Input = enum(u32) { name = 1, checked = 2 };
const Row = struct { id: u32, label: []const u8 };
const View = struct {
    prefix: []const u8 = "",
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

test "nested components derive exact capacity and update one instance without ancestor patches" {
    const component = @import("components").Scoped(.{ .first = 500, .count = 100 });
    const CP = gui.Projection(component.snapshot_capacity);
    const Field = struct { label: []const u8, value: []const u8 };
    var model: struct { left: Field, right: struct { field: Field } } = .{ .left = Field{ .label = "Left", .value = "one" }, .right = .{ .field = Field{ .label = "Right", .value = "two" } } };
    try std.testing.expectEqual(@as(usize, 4), component.snapshot_capacity);
    try std.testing.expect(component.nodes.@"left.input" != component.nodes.@"right.inner.input");
    var bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var previous = CP.Snapshot{};
    var p = CP{ .html = &html, .next = &previous };
    component.project(&p, model);
    try std.testing.expect(!html.failed);
    try std.testing.expectEqual(component.snapshot_capacity, previous.len);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "<template") == null);
    var output_bytes: [512]u8 = undefined;
    var output = gui.html.Writer{ .buffer = &output_bytes };
    var patches = gui.patch.Writer{ .output = &output };
    var next = CP.Snapshot{};
    p = .{ .html = &html, .next = &next, .previous = &previous, .patches = &patches, .writing = false };
    model.left.value = "changed";
    component.project(&p, model);
    try std.testing.expect(!html.failed and !output.failed);
    var expected: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "V\t{d}\t\"changed\"\n", .{component.nodes.@"left.input"}), output.slice());
    previous = next;
    next = .{};
    output.len = 0;
    component.project(&p, model);
    try std.testing.expectEqual(@as(usize, 0), output.len);
    // Full recovery projects both current instances, never cached template input.
    html.len = 0;
    next = .{};
    p = .{ .html = &html, .next = &next };
    component.project(&p, model);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "changed") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "two") != null);
}

test "component snapshot HTML and namespace exhaustion reject the candidate projection" {
    const component = @import("components");
    const model = .{ .left = .{ .label = "Left", .value = "one" }, .right = .{ .field = .{ .label = "Right", .value = "two" } } };
    const Small = gui.Projection(component.snapshot_capacity - 1);
    var bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var snapshot = Small.Snapshot{};
    var p = Small{ .html = &html, .next = &snapshot };
    component.project(&p, model);
    try std.testing.expect(html.failed);
    const Full = gui.Projection(component.snapshot_capacity);
    var full_snapshot = Full.Snapshot{};
    var full = Full{ .html = &html, .next = &full_snapshot };
    html = .{ .buffer = bytes[0..8] };
    component.project(&full, model);
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    full_snapshot = .{};
    component.Scoped(.{ .first = 1, .count = 2 }).project(&full, model);
    try std.testing.expect(html.failed);
}

test "runtime placement shares checked refs and rejects invalid ranges before writing" {
    const component = @import("components");
    const Model = struct { label: []const u8, value: []const u8 };
    const model = .{ .left = Model{ .label = "Left", .value = "one" }, .right = .{ .field = Model{ .label = "Right", .value = "two" } } };
    const CP = gui.Projection(component.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var snapshot = CP.Snapshot{};
    var p = CP{ .html = &html, .next = &snapshot };
    var first: u32 = 600;
    _ = &first;
    const space = gui.template.Namespace{ .first = first, .count = 100 };
    const refs = try component.nodesAt(space);
    component.projectAt(&p, model, space);
    var expected: [64]u8 = undefined;
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), try std.fmt.bufPrint(&expected, "data-node-id=\"{d}\"", .{refs.@"left.input"})) != null);
    try std.testing.expectEqual(component.snapshot_capacity, snapshot.len);
    for ([_]gui.template.Namespace{
        .{ .first = 0, .count = 100 },
        .{ .first = 1, .count = 0 },
        .{ .first = 1, .count = 2 },
        .{ .first = std.math.maxInt(u32) - 1, .count = 100 },
    }) |invalid| {
        html = .{ .buffer = &bytes };
        snapshot = .{};
        try std.testing.expectError(error.NamespaceOverflow, component.nodesAt(invalid));
        component.projectAt(&p, model, invalid);
        try std.testing.expect(html.failed and html.len == 0 and snapshot.len == 0);
    }
}

test "dynamic input prefixes use a named attribute leaf" {
    var h = Harness{};
    var model = View{};
    _ = try h.render(.{ .value = model, .mode = .full });
    model.prefix = "12:";
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("A\t{d}\tdata-input-prefix\t12:\n", .{view.nodes.input}), try h.render(.{ .value = model, .mode = .patch }));
}

test "list fragments retain owner and row controls across text patches" {
    const list = @import("list").Scoped(.{ .first = 100, .count = 10 });
    const row = @import("list_row");
    const Rows = struct {
        label: []const u8,
        pub fn project(value: @This(), p: anytype, owner: struct { node: u32 }) void {
            std.debug.assert(owner.node == list.nodes.list);
            row.projectAt(p, .{ .label = value.label, .action = Action.increment }, .{ .first = 200, .count = 10 });
        }
    };
    const ListP = gui.Projection(list.snapshot_capacity + row.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var commands: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &commands };
    var writer = gui.patch.Writer{ .output = &output };
    var before = ListP.Snapshot{};
    var p = ListP{ .html = &html, .next = &before };
    list.project(&p, .{ .rows = Rows{ .label = "One & <two>" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "One &amp; &lt;two&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "<li") != null);
    var next = ListP.Snapshot{};
    p = .{ .html = &html, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    list.project(&p, .{ .rows = Rows{ .label = "Updated" } });
    const refs = try row.nodesAt(.{ .first = 200, .count = 10 });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("T\t{d}\t\"Updated\"\n", .{201}), output.slice());
    try std.testing.expectEqual(@as(u32, 201), refs.label);
    html = .{ .buffer = &bytes };
    next = .{};
    p = .{ .html = &html, .next = &next };
    row.projectAt(&p, .{ .label = "Rejected", .action = Action.increment }, .{ .first = 200, .count = 1 });
    try std.testing.expect(html.failed);
    try std.testing.expectEqual(@as(usize, 0), html.len);
    try std.testing.expectEqual(@as(usize, 0), next.len);
}

test "table fragments retain owner and row controls across text patches" {
    const list = @import("table").Scoped(.{ .first = 100, .count = 10 });
    const row = @import("table_row");
    const Rows = struct {
        label: []const u8,
        pub fn project(value: @This(), p: anytype, owner: struct { node: u32 }) void {
            std.debug.assert(owner.node == list.nodes.list);
            row.projectAt(p, .{ .label = value.label, .action = Action.increment }, .{ .first = 200, .count = 10 });
        }
    };
    const ListP = gui.Projection(list.snapshot_capacity + row.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var commands: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &commands };
    var writer = gui.patch.Writer{ .output = &output };
    var before = ListP.Snapshot{};
    var p = ListP{ .html = &html, .next = &before };
    list.project(&p, .{ .rows = Rows{ .label = "One & <two>" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "One &amp; &lt;two&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "<tr") != null);
    var next = ListP.Snapshot{};
    p = .{ .html = &html, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    list.project(&p, .{ .rows = Rows{ .label = "Updated" } });
    const refs = try row.nodesAt(.{ .first = 200, .count = 10 });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("T\t{d}\t\"Updated\"\n", .{201}), output.slice());
    try std.testing.expectEqual(@as(u32, 201), refs.label);
    html = .{ .buffer = &bytes };
    next = .{};
    p = .{ .html = &html, .next = &next };
    row.projectAt(&p, .{ .label = "Rejected", .action = Action.increment }, .{ .first = 200, .count = 1 });
    try std.testing.expect(html.failed);
    try std.testing.expectEqual(@as(usize, 0), html.len);
    try std.testing.expectEqual(@as(usize, 0), next.len);
}

test "select slot membership updates only its options and preserves value binding" {
    const template = @import("select_slot").Scoped(.{ .first = 100, .count = 10 });
    const Options = struct {
        label: []const u8,
        pub fn project(value: @This(), p: anytype, owner: struct { node: u32 }) void {
            const list = p.beginList(.{ .node = owner.node, .membership = value.label });
            p.add("<option value=\"a\">");
            p.escaped(value.label);
            p.add("</option>");
            p.endList(list);
        }
    };
    const SP = gui.Projection(template.snapshot_capacity + 1);
    var bytes: [2048]u8 = undefined;
    var commands: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &commands };
    var writer = gui.patch.Writer{ .output = &output };
    var before = SP.Snapshot{};
    var p = SP{ .html = &html, .next = &before };
    template.project(&p, .{ .selected = "a", .options = Options{ .label = "One & two" } });
    try std.testing.expect(!html.failed);
    try std.testing.expectEqual(template.snapshot_capacity + 1, before.len);
    var next = SP.Snapshot{};
    p = .{ .html = &html, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    template.project(&p, .{ .selected = "a", .options = Options{ .label = "Three <four>" } });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("H\t{d}\t\"<option value=\\\"a\\\">Three &lt;four&gt;</option>\"\n", .{template.nodes.select}), output.slice());
    output = .{ .buffer = commands[0..1] };
    next = .{};
    template.project(&p, .{ .selected = "a", .options = Options{ .label = "Another" } });
    try std.testing.expect(output.failed);
}

test "generated time updates only text and optional datetime with bounded output" {
    const time = @import("time_fixture");
    const Projection = gui.Projection(time.snapshot_capacity);
    var previous = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var html_bytes: [1024]u8 = undefined;
    var output_bytes: [1024]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &html_bytes };
    var output = gui.html.Writer{ .buffer = &output_bytes };
    var writer = gui.patch.Writer{ .output = &output };
    var p = Projection{ .html = &html, .next = &previous };
    time.project(&p, .{ .instant = @as(?[]const u8, "2030-10-01"), .label = "A < B & C" });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "A &lt; B &amp; C") != null);
    try std.testing.expectEqual(time.snapshot_capacity, previous.len);
    p = .{ .html = &html, .patches = &writer, .previous = &previous, .next = &next, .writing = false };
    time.project(&p, .{ .instant = @as(?[]const u8, null), .label = "Tomorrow" });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("R\t{d}\tdatetime\nT\t{d}\t\"Tomorrow\"\n", .{ time.nodes.time, time.nodes.time }), output.slice());
    output = .{ .buffer = output_bytes[0..1] };
    next = .{};
    time.project(&p, .{ .instant = @as(?[]const u8, "2030-10-02"), .label = "Later" });
    try std.testing.expect(output.failed);
}

test "radio values retain generated checked ownership and reject truncated commands" {
    const radio = @import("radio_fixture");
    const Projection = gui.Projection(radio.snapshot_capacity);
    var previous = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var html_bytes: [2048]u8 = undefined;
    var output_bytes: [256]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &html_bytes };
    var output = gui.html.Writer{ .buffer = &output_bytes };
    var writer = gui.patch.Writer{ .output = &output };
    var p = Projection{ .html = &html, .next = &previous };
    radio.project(&p, .{ .input = Input.checked, .one = true, .all = false });
    try std.testing.expect(!html.failed);
    try std.testing.expectEqual(radio.snapshot_capacity, previous.len);
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, html.slice(), "data-value-format=\"value\""));
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "data-value-format=\"checked\"") == null);
    p = .{ .html = &html, .patches = &writer, .previous = &previous, .next = &next, .writing = false };
    radio.project(&p, .{ .input = Input.checked, .one = false, .all = true });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("C\t{d}\tfalse\nC\t{d}\ttrue\n", .{ radio.nodes.one, radio.nodes.all }), output.slice());
    next = .{};
    output = .{ .buffer = output_bytes[0..1] };
    radio.project(&p, .{ .input = Input.checked, .one = false, .all = true });
    try std.testing.expect(output.failed);
}

test "generated drag eligibility preserves enumerated values and leaf ownership" {
    const drag = @import("drag_fixture");
    const Projection = gui.Projection(drag.snapshot_capacity);
    var previous = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var html_bytes: [1024]u8 = undefined;
    var output_bytes: [256]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &html_bytes };
    var output = gui.html.Writer{ .buffer = &output_bytes };
    var writer = gui.patch.Writer{ .output = &output };
    var p = Projection{ .html = &html, .next = &previous };
    drag.project(&p, .{ .drag = @as(?[]const u8, "true") });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "draggable=\"true\"") != null);
    try std.testing.expectEqual(drag.snapshot_capacity, previous.len);
    for ([_]?[]const u8{ "false", "auto", null }) |value| {
        next = .{};
        output.len = 0;
        p = .{ .html = &html, .patches = &writer, .previous = &previous, .next = &next, .writing = false };
        drag.project(&p, .{ .drag = value });
        var expected: [128]u8 = undefined;
        const command = if (value) |v| try std.fmt.bufPrint(&expected, "A\t{d}\tdraggable\t{s}\n", .{ drag.nodes.handle, v }) else try std.fmt.bufPrint(&expected, "R\t{d}\tdraggable\n", .{drag.nodes.handle});
        try std.testing.expectEqualStrings(command, output.slice());
        previous = next;
    }
    output = .{ .buffer = output_bytes[0..1] };
    next = .{};
    drag.project(&p, .{ .drag = @as(?[]const u8, "true") });
    try std.testing.expect(output.failed);
}
