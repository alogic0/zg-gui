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

test "static HTML rendering produces clean markup without snapshot or patch overhead" {
    var bytes: [8192]u8 = undefined;
    var writer = gui.html.Writer{ .buffer = &bytes };
    const model = View{ .count = 7, .name = "Static <Page>", .disabled = true };

    // Clean SSR markup (no data-node-id)
    view.renderHtml(&writer, model);
    try std.testing.expect(!writer.failed);
    const html_clean = writer.slice();
    try std.testing.expect(std.mem.indexOf(u8, html_clean, "Static &lt;Page&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html_clean, "data-node-id=") == null);
    try std.testing.expect(std.mem.indexOf(u8, html_clean, " disabled") != null);
    try std.testing.expect(std.mem.indexOf(u8, html_clean, "disabled=\"\"") == null);

    // Hydration-ready SSR markup (with data-node-id)
    writer.len = 0;
    view.renderHtmlWithNodes(&writer, model);
    try std.testing.expect(!writer.failed);
    const html_hydrated = writer.slice();
    try std.testing.expect(std.mem.indexOf(u8, html_hydrated, "Static &lt;Page&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, html_hydrated, "data-node-id=") != null);
    try std.testing.expect(std.mem.indexOf(u8, html_hydrated, " disabled") != null);
    try std.testing.expect(std.mem.indexOf(u8, html_hydrated, "disabled=\"\"") == null);
}

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

test "integer layout variables update leaves and reject overflow or short output" {
    const template = @import("style_fixture");
    const LayoutProjection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = LayoutProjection.Snapshot{};
    var p = LayoutProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .layout = .{ .@"--gap" = @as(i64, -12), .@"--extent" = @as(u64, 200) } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "data-style-vars=\"--gap:-12;--extent:200\"") != null);
    try std.testing.expectEqual(template.snapshot_capacity, before.len);
    var after = LayoutProjection.Snapshot{};
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .previous = &before, .next = &after, .writing = false };
    template.project(&p, .{ .layout = .{ .@"--gap" = @as(i64, 0), .@"--extent" = @as(u64, 400) } });
    var expected: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "A\t{d}\tdata-style-vars\t--gap:0;--extent:400\n", .{template.nodes.spacer}), html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    var limited_writer = gui.patch.Writer{ .output = &limited };
    p.patches = &limited_writer;
    after = .{};
    template.project(&p, .{ .layout = .{ .@"--gap" = @as(i64, 0), .@"--extent" = @as(u64, 400) } });
    try std.testing.expect(limited.failed);
    html.len = 0;
    p.patches = &writer;
    after = .{};
    template.project(&p, .{ .layout = .{ .@"--gap" = @as(i64, 0), .@"--extent" = @as(u64, 400) } });
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "A\t{d}\tdata-style-vars\t--gap:0;--extent:400\n", .{template.nodes.spacer}), html.slice());
    html.len = 0;
    template.project(&p, .{ .layout = .{ .@"--gap" = @as(i64, 0), .@"--extent" = std.math.maxInt(u64) } });
    try std.testing.expect(scratch.failed and html.len == 0);
}

test "generated image sources escape update remove and reject unsafe values" {
    const image = @import("image_fixture");
    const ImageProjection = gui.Projection(image.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = ImageProjection.Snapshot{};
    var after = ImageProjection.Snapshot{};
    var p = ImageProjection{ .html = &html, .next = &before };
    image.project(&p, .{ .source = @as(?[]const u8, "https://images.example.test/a?x=1&y=2") });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "x=1&amp;y=2") != null);
    try std.testing.expectEqual(image.snapshot_capacity, before.len);
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .previous = &before, .next = &after, .writing = false };
    for ([_]?[]const u8{ "/image.png", null }) |source| {
        html.len = 0;
        after = .{};
        image.project(&p, .{ .source = source });
        var expected: [128]u8 = undefined;
        const command = if (source) |v| try std.fmt.bufPrint(&expected, "A\t{d}\tsrc\t{s}\n", .{ image.nodes.image, v }) else try std.fmt.bufPrint(&expected, "R\t{d}\tsrc\n", .{image.nodes.image});
        try std.testing.expectEqualStrings(command, html.slice());
    }
    for ([_][]const u8{ "", "//outside.test/a", "javascript:alert(1)", "data:image/png,x", "https://user:pass@example.test/a", "https://example.test/\\a", "https://example.test/\nx" }) |source| {
        html.len = 0;
        scratch.failed = false;
        image.project(&p, .{ .source = source });
        try std.testing.expect(scratch.failed and html.len == 0);
    }
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    scratch.failed = false;
    after = .{};
    image.project(&p, .{ .source = "/retry.png" });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    image.project(&p, .{ .source = "/retry.png" });
    try std.testing.expect(!scratch.failed and std.mem.indexOf(u8, html.slice(), "/retry.png") != null);
}

test "description slot child updates retain semantic owners and retry failed output" {
    const template = @import("description_slot").Scoped(.{ .first = 200, .count = 16 });
    const Children = struct {
        text: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            p.add("<span");
            p.node(300);
            p.add(">");
            p.text(.{ .node = 300, .value = self.text });
            p.add("</span>");
        }
    };
    const DescriptionProjection = gui.Projection(template.snapshot_capacity + 1);
    var bytes: [2048]u8 = undefined;
    var temporary: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &temporary };
    var before = DescriptionProjection.Snapshot{};
    var after = DescriptionProjection.Snapshot{};
    var p = DescriptionProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .children = Children{ .text = "Before < &" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "Before &lt; &amp;") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .next = &after, .previous = &before, .writing = false };
    template.project(&p, .{ .children = Children{ .text = "After" } });
    try std.testing.expectEqualStrings("T\t300\t\"After\"\n", html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expectEqualStrings("T\t300\t\"Retry\"\n", html.slice());
}

test "compiled option group projects leaves with bounded failure and retry" {
    const select = @import("select_slot").Scoped(.{ .first = 100, .count = 10 });
    const group = @import("option_group").Scoped(.{ .first = 120, .count = 10 });
    const option = @import("option").Scoped(.{ .first = 140, .count = 1 });
    const Options = struct {
        label: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            option.project(p, .{ .value = "a", .label = self.label, .disabled = false });
        }
    };
    const Group = struct {
        label: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            group.project(p, .{ .options = Options{ .label = self.label } });
        }
    };
    const SP = gui.Projection(select.snapshot_capacity + group.snapshot_capacity + option.snapshot_capacity);
    var bytes: [4096]u8 = undefined;
    var commands: [4096]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &commands };
    var writer = gui.patch.Writer{ .output = &output };
    var previous = SP.Snapshot{};
    var next = SP.Snapshot{};
    var p = SP{ .html = &html, .next = &previous };
    select.project(&p, .{ .selected = "a", .options = Group{ .label = "One & two" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "One &amp; two") != null);
    p = .{ .html = &html, .next = &next, .previous = &previous, .patches = &writer, .writing = false };
    output = .{ .buffer = commands[0..1] };
    select.project(&p, .{ .selected = "a", .options = Group{ .label = "Changed" } });
    try std.testing.expect(output.failed);
    next = .{};
    output = .{ .buffer = &commands };
    select.project(&p, .{ .selected = "a", .options = Group{ .label = "Changed" } });
    try std.testing.expect(!output.failed and !html.failed);
    try std.testing.expectEqualStrings("T\t140\t\"Changed\"\n", output.slice());
}

test "meter bounds reject invalid candidates and retry only the level leaf" {
    const meter = @import("meter").Scoped(.{ .first = 200, .count = 4 });
    const MP = gui.Projection(meter.snapshot_capacity);
    var bytes: [1024]u8 = undefined;
    var commands: [1024]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &commands };
    var writer = gui.patch.Writer{ .output = &output };
    var before = MP.Snapshot{};
    var next = MP.Snapshot{};
    var p = MP{ .html = &html, .next = &before };
    meter.project(&p, .{ .level = @as(u8, 0) });
    try std.testing.expect(!html.failed);
    try std.testing.expectEqual(@as(usize, 1), before.len);
    p = .{ .html = &html, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    for ([_]i64{ -1, 101, 4294967296 }) |invalid| {
        html.failed = false;
        next = .{};
        meter.project(&p, .{ .level = invalid });
        try std.testing.expect(html.failed);
        try std.testing.expectEqual(@as(usize, 0), output.len);
    }
    html.failed = false;
    next = .{};
    output = .{ .buffer = commands[0..1] };
    meter.project(&p, .{ .level = @as(u8, 100) });
    try std.testing.expect(output.failed);
    next = .{};
    output = .{ .buffer = &commands };
    meter.project(&p, .{ .level = @as(u8, 100) });
    try std.testing.expect(!html.failed and !output.failed);
    try std.testing.expectEqualStrings("A\t201\tvalue\t100\n", output.slice());
}

test "navigation child updates retain semantic owners and retry failed output" {
    const template = @import("navigation_slot").Scoped(.{ .first = 200, .count = 16 });
    const Children = struct {
        text: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            p.add("<span");
            p.node(300);
            p.add(">");
            p.text(.{ .node = 300, .value = self.text });
            p.add("</span>");
        }
    };
    const NavigationProjection = gui.Projection(template.snapshot_capacity + 1);
    var bytes: [2048]u8 = undefined;
    var temporary: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &temporary };
    var before = NavigationProjection.Snapshot{};
    var after = NavigationProjection.Snapshot{};
    var p = NavigationProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .children = Children{ .text = "Before < &" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "Before &lt; &amp;") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .next = &after, .previous = &before, .writing = false };
    template.project(&p, .{ .children = Children{ .text = "After" } });
    try std.testing.expectEqualStrings("T\t300\t\"After\"\n", html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expectEqualStrings("T\t300\t\"Retry\"\n", html.slice());
}

test "mapped component refs and leaf patches retain external identities" {
    const source = @import("components");
    const mapped = source.Scoped(.{ .first = 800, .count = 100, .overrides = &.{.{ .local = source.nodes.@"left.input", .node = 42 }} });
    const CP = gui.Projection(mapped.snapshot_capacity);
    var bytes: [4096]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var previous = CP.Snapshot{};
    var p = CP{ .html = &html, .next = &previous };
    const Field = struct { label: []const u8, value: []const u8 };
    var model: struct { left: Field, right: struct { field: Field } } = .{ .left = .{ .label = "Left", .value = "one" }, .right = .{ .field = .{ .label = "Right", .value = "two" } } };
    mapped.project(&p, model);
    try std.testing.expect(!html.failed);
    try std.testing.expectEqual(@as(u32, 42), mapped.nodes.@"left.input");
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "data-node-id=\"42\"") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    var scratch = gui.html.Writer{ .buffer = &.{} };
    var next = CP.Snapshot{};
    p = .{ .html = &scratch, .patches = &writer, .previous = &previous, .next = &next, .writing = false };
    model.left.value = "changed";
    mapped.project(&p, model);
    try std.testing.expect(!html.failed and !scratch.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "H\t") == null);
    html.len = 0;
    next = .{};
    p = .{ .html = &html, .next = &next };
    source.projectAt(&p, model, .{ .first = 800, .count = 100, .overrides = &.{.{ .local = 1, .node = 801 }} });
    try std.testing.expect(html.failed and html.len == 0 and next.len == 0);
}

test "generated local links escape query attributes and patch the anchor alone" {
    const component = @import("link_fixture");
    const CP = gui.Projection(component.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var previous = CP.Snapshot{};
    var p = CP{ .html = &html, .next = &previous };
    component.project(&p, .{ .path = "/items?q=a&sort=b#row", .label = "Items" });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "q=a&amp;sort=b") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    var scratch = gui.html.Writer{ .buffer = &.{} };
    var next = CP.Snapshot{};
    p = .{ .html = &scratch, .patches = &writer, .previous = &previous, .next = &next, .writing = false };
    component.project(&p, .{ .path = "/items/2", .label = "Items" });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("A\t{d}\thref\t/items/2\n", .{component.nodes.link}), html.slice());
}

test "description list child updates retain semantic owners and retry failed output" {
    const template = @import("description_list").Scoped(.{ .first = 200, .count = 16 });
    const Children = struct {
        text: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            p.add("<div><dt>Value</dt><dd");
            p.node(300);
            p.add(">");
            p.text(.{ .node = 300, .value = self.text });
            p.add("</dd></div>");
        }
    };
    const DescriptionProjection = gui.Projection(template.snapshot_capacity + 1);
    var bytes: [2048]u8 = undefined;
    var temporary: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &temporary };
    var before = DescriptionProjection.Snapshot{};
    var after = DescriptionProjection.Snapshot{};
    var p = DescriptionProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .children = Children{ .text = "Before < &" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "Before &lt; &amp;") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .next = &after, .previous = &before, .writing = false };
    template.project(&p, .{ .children = Children{ .text = "After" } });
    try std.testing.expectEqualStrings("T\t300\t\"After\"\n", html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expectEqualStrings("T\t300\t\"Retry\"\n", html.slice());
}

test "aside child updates retain semantic owners and retry failed output" {
    const template = @import("aside_slot").Scoped(.{ .first = 200, .count = 16 });
    const Children = struct {
        text: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            p.add("<p");
            p.node(300);
            p.add(">");
            p.text(.{ .node = 300, .value = self.text });
            p.add("</p>");
        }
    };
    const AsideProjection = gui.Projection(template.snapshot_capacity + 1);
    var bytes: [2048]u8 = undefined;
    var temporary: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &temporary };
    var before = AsideProjection.Snapshot{};
    var after = AsideProjection.Snapshot{};
    var p = AsideProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .children = Children{ .text = "Before < &" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "Before &lt; &amp;") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .next = &after, .previous = &before, .writing = false };
    template.project(&p, .{ .children = Children{ .text = "After" } });
    try std.testing.expectEqualStrings("T\t300\t\"After\"\n", html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expectEqualStrings("T\t300\t\"Retry\"\n", html.slice());
}

test "dimensional style variables retain owners through changes and retry" {
    const template = @import("style_fixture");
    const Value = gui.template.StyleValue;
    const Layout = struct { @"--x": Value, @"--opacity": Value, @"--count": i64 };
    const layout = Layout{ .@"--x" = .{ .value = std.math.minInt(i64), .unit = .px }, .@"--opacity" = .{ .value = 80, .unit = .percent }, .@"--count" = std.math.maxInt(i64) };
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [4096]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var first = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &first };
    template.project(&p, .{ .layout = layout });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "--x:-9223372036854775808px;--opacity:80%;--count:9223372036854775807") != null);
    var next = Projection.Snapshot{};
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &html, .next = &next, .previous = &first, .patches = &writer, .writing = false };
    template.project(&p, .{ .layout = Layout{ .@"--x" = .{ .value = 4, .unit = .px }, .@"--opacity" = .{ .value = 100, .unit = .percent }, .@"--count" = 0 } });
    var expected: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "A\t{d}\tdata-style-vars\t--x:4px;--opacity:100%;--count:0\n", .{template.nodes.spacer}), html.slice());
    const changed = next;
    var tiny: [1]u8 = undefined;
    html = .{ .buffer = &tiny };
    next = .{};
    p = .{ .html = &html, .next = &next, .previous = &changed, .patches = &writer, .writing = false };
    template.project(&p, .{ .layout = layout });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    next = .{};
    template.project(&p, .{ .layout = layout });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.startsWith(u8, html.slice(), "A\t"));
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "H\t") == null);
}

test "tab order changes retain composite controls and support attribute removal" {
    const template = @import("tab_order");
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [4096]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var first = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &first };
    template.project(&p, .{ .first = @as(?i16, 0), .second = @as(i16, -1) });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "tabindex=\"-1\"") != null);
    var next = Projection.Snapshot{};
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &html, .next = &next, .previous = &first, .patches = &writer, .writing = false };
    template.project(&p, .{ .first = @as(?i16, null), .second = @as(i16, 0) });
    var expected: [256]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "R\t{d}\ttabindex\nA\t{d}\ttabindex\t0\n", .{ template.nodes.first, template.nodes.second }), html.slice());
}

test "progress bounds reject invalid candidates and retry only the level leaf" {
    const meter = @import("progress").Scoped(.{ .first = 200, .count = 4 });
    const MP = gui.Projection(meter.snapshot_capacity);
    var bytes: [1024]u8 = undefined;
    var commands: [1024]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &commands };
    var writer = gui.patch.Writer{ .output = &output };
    var before = MP.Snapshot{};
    var next = MP.Snapshot{};
    var p = MP{ .html = &html, .next = &before };
    meter.project(&p, .{ .maximum = @as(f64, 100), .level = @as(f64, 0.25) });
    try std.testing.expect(!html.failed);
    try std.testing.expectEqual(@as(usize, 2), before.len);
    p = .{ .html = &html, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    for ([_]f64{ -1, 100.01, std.math.nan(f64), std.math.inf(f64) }) |invalid| {
        html.failed = false;
        next = .{};
        meter.project(&p, .{ .maximum = @as(f64, 100), .level = invalid });
        try std.testing.expect(html.failed);
        try std.testing.expectEqual(@as(usize, 0), output.len);
    }
    for ([_]f64{ 0, -1, std.math.nan(f64), std.math.inf(f64), 0.1 }) |invalid| {
        html.failed = false;
        next = .{};
        meter.project(&p, .{ .maximum = invalid, .level = @as(f64, 0.25) });
        try std.testing.expect(html.failed);
        try std.testing.expectEqual(@as(usize, 0), output.len);
    }
    html.failed = false;
    next = .{};
    output = .{ .buffer = commands[0..1] };
    meter.project(&p, .{ .maximum = @as(f64, 100), .level = @as(f64, 99.75) });
    try std.testing.expect(output.failed);
    next = .{};
    output = .{ .buffer = &commands };
    meter.project(&p, .{ .maximum = @as(f64, 100), .level = @as(f64, 99.75) });
    try std.testing.expect(!html.failed and !output.failed);
    try std.testing.expectEqualStrings("A\t201\tvalue\t99.75\n", output.slice());
    next = .{};
    output.len = 0;
    meter.project(&p, .{ .maximum = @as(f64, 250.5), .level = @as(f64, 200.25) });
    try std.testing.expectEqualStrings("A\t201\tmax\t250.5\nA\t201\tvalue\t200.25\n", output.slice());
}

test "list item child updates retain semantic owners and retry failed output" {
    const template = @import("list_item_slot").Scoped(.{ .first = 200, .count = 16 });
    const Children = struct {
        text: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            p.add("<p");
            p.node(300);
            p.add(">");
            p.text(.{ .node = 300, .value = self.text });
            p.add("</p>");
        }
    };
    const ItemProjection = gui.Projection(template.snapshot_capacity + 1);
    var bytes: [2048]u8 = undefined;
    var temporary: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &temporary };
    var before = ItemProjection.Snapshot{};
    var after = ItemProjection.Snapshot{};
    var p = ItemProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .children = Children{ .text = "Before < &" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "Before &lt; &amp;") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .next = &after, .previous = &before, .writing = false };
    template.project(&p, .{ .children = Children{ .text = "After" } });
    try std.testing.expectEqualStrings("T\t300\t\"After\"\n", html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" } });
    try std.testing.expectEqualStrings("T\t300\t\"Retry\"\n", html.slice());
}

test "phrasing child updates retain semantic owners and retry failed output" {
    const template = @import("phrasing_slot").Scoped(.{ .first = 200, .count = 16 });
    const Children = struct {
        text: []const u8,
        pub fn project(self: @This(), p: anytype, _: struct { node: u32 }) void {
            p.add("<span");
            p.node(300);
            p.add(">");
            p.text(.{ .node = 300, .value = self.text });
            p.add("</span>");
        }
    };
    const OptionText = struct {
        pub fn project(_: @This(), p: anytype, owner: struct { node: u32 }) void {
            p.text(.{ .node = owner.node, .value = "A < B" });
        }
    };
    const PhrasingProjection = gui.Projection(template.snapshot_capacity + 2);
    var bytes: [2048]u8 = undefined;
    var temporary: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &temporary };
    var before = PhrasingProjection.Snapshot{};
    var after = PhrasingProjection.Snapshot{};
    var p = PhrasingProjection{ .html = &html, .next = &before };
    template.project(&p, .{ .children = Children{ .text = "Before < &" }, .option = OptionText{} });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "Before &lt; &amp;") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .patches = &writer, .next = &after, .previous = &before, .writing = false };
    template.project(&p, .{ .children = Children{ .text = "After" }, .option = OptionText{} });
    try std.testing.expectEqualStrings("T\t300\t\"After\"\n", html.slice());
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" }, .option = OptionText{} });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .children = Children{ .text = "Retry" }, .option = OptionText{} });
    try std.testing.expectEqualStrings("T\t300\t\"Retry\"\n", html.slice());
}

test "embedded document updates remain leaves and retry failed publication" {
    const frame = @import("embedded_document").Scoped(.{ .first = 500, .count = 8 });
    const FrameProjection = gui.Projection(frame.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = FrameProjection.Snapshot{};
    var after = FrameProjection.Snapshot{};
    var p = FrameProjection{ .html = &html, .next = &before };
    frame.project(&p, .{ .source = "/preview?a=1&b=2", .visible = true });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "/preview?a=1&amp;b=2") != null);
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    var writer = gui.patch.Writer{ .output = &limited };
    p = .{ .html = &scratch, .patches = &writer, .previous = &before, .next = &after, .writing = false };
    frame.project(&p, .{ .source = "about:blank", .visible = false });
    try std.testing.expect(limited.failed);
    html.len = 0;
    writer.output = &html;
    after = .{};
    frame.project(&p, .{ .source = "about:blank", .visible = false });
    try std.testing.expect(!html.failed and !scratch.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), std.fmt.comptimePrint("A\t{d}\tsrc\tabout:blank\n", .{frame.nodes.frame})) != null);
}

test "native field constraints retain the control and retry failed output" {
    const template = @import("native_constraints");
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var output = gui.html.Writer{ .buffer = &bytes };
    var before = Projection.Snapshot{};
    var after = Projection.Snapshot{};
    var p = Projection{ .html = &output, .next = &before };
    const ConstraintView = struct { value: []const u8, required: bool, min: ?[]const u8, max: ?[]const u8, step: ?[]const u8 };
    template.project(&p, ConstraintView{ .value = "12", .required = false, .min = "0", .max = "20", .step = "1" });
    try std.testing.expect(!output.failed);
    var scratch_bytes: [2048]u8 = undefined;
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    var writer = gui.patch.Writer{ .output = &limited };
    p = .{ .html = &scratch, .next = &after, .previous = &before, .patches = &writer, .writing = false };
    const changed = ConstraintView{ .value = "12", .required = true, .min = "5", .max = null, .step = "any" };
    template.project(&p, changed);
    try std.testing.expect(limited.failed);
    output.len = 0;
    writer.output = &output;
    after = .{};
    template.project(&p, changed);
    try std.testing.expect(!output.failed and !scratch.failed);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "\trequired\t\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "\tmax\n") != null);
}

test "explicit external links escape, reject unsafe destinations and remove href" {
    const template = @import("external_link");
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var before = Projection.Snapshot{};
    var after = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &before };
    template.project(&p, .{ .href = "https://example.test/?a=1&b=2" });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "?a=1&amp;b=2") != null);
    html.len = 0;
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &html, .next = &after, .previous = &before, .patches = &writer, .writing = false };
    var tiny: [1]u8 = undefined;
    var limited = gui.html.Writer{ .buffer = &tiny };
    writer.output = &limited;
    template.project(&p, .{ .href = @as(?[]const u8, null) });
    try std.testing.expect(limited.failed);
    writer.output = &html;
    after = .{};
    template.project(&p, .{ .href = @as(?[]const u8, null) });
    try std.testing.expectEqualStrings(std.fmt.comptimePrint("R\t{d}\thref\n", .{template.nodes.link}), html.slice());
    for ([_][]const u8{ "", "http://example.test", "//example.test", "javascript:alert(1)", "https://u:p@example.test", "https://example.test/\n" }) |value| {
        html = .{ .buffer = &bytes };
        before = .{};
        p = .{ .html = &html, .next = &before };
        template.project(&p, .{ .href = value });
        try std.testing.expect(html.failed);
    }
}

test "row cell composition retains parents and retries rejected output" {
    const row = @import("table_slot_row").Scoped(.{ .first = 100, .count = 10 });
    const cells = @import("table_cells").Scoped(.{ .first = 200, .count = 10 });
    const Children = struct {
        label: []const u8,
        pub fn project(value: @This(), p: anytype, owner: struct { node: u32 }) void {
            std.debug.assert(owner.node == row.nodes.row);
            cells.project(p, .{ .label = value.label, .draft = "keep" });
        }
    };
    const CellP = gui.Projection(row.snapshot_capacity + cells.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var commands: [2048]u8 = undefined;
    var tiny: [1]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &tiny };
    var writer = gui.patch.Writer{ .output = &output };
    var before = CellP.Snapshot{};
    var p = CellP{ .html = &html, .next = &before };
    row.project(&p, .{ .cells = Children{ .label = "One & <two>" } });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "One &amp; &lt;two&gt;") != null);
    var next = CellP.Snapshot{};
    p = .{ .html = &html, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    row.project(&p, .{ .cells = Children{ .label = "Updated" } });
    try std.testing.expect(output.failed);
    output = .{ .buffer = &commands };
    next = .{};
    row.project(&p, .{ .cells = Children{ .label = "Updated" } });
    try std.testing.expectEqualStrings("T\t200\t\"Updated\"\n", output.slice());
}

test "fragment and explicitly permitted HTTP links retain leaves and retry" {
    const template = @import("navigation_link").Scoped(.{ .first = 500, .count = 8 });
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [1]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &before };
    template.project(&p, .{ .anchor = "#section-1", .resource = "http://example.test/one?a=1&b=2" });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "a=1&amp;b=2") != null);
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    html = .{ .buffer = bytes[0..1] };
    template.project(&p, .{ .anchor = "#section-2", .resource = @as(?[]const u8, "http://example.test/two") });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    next = .{};
    template.project(&p, .{ .anchor = "#section-2", .resource = @as(?[]const u8, "http://example.test/two") });
    try std.testing.expect(!html.failed and !scratch.failed);
    try std.testing.expectEqualStrings("A\t501\thref\t#section-2\nA\t502\thref\thttp://example.test/two\n", html.slice());
    for ([_][]const u8{ "#", "//example.test", "#bad\n", "javascript:alert(1)" }) |bad| {
        html = .{ .buffer = &bytes };
        next = .{};
        p = .{ .html = &html, .next = &next };
        template.project(&p, .{ .anchor = bad, .resource = "https://example.test" });
        try std.testing.expect(html.failed);
    }
    for ([_][]const u8{ "http://u:p@example.test", "javascript:alert(1)", "//example.test", "http://example.test/\n" }) |bad| {
        html = .{ .buffer = &bytes };
        next = .{};
        p = .{ .html = &html, .next = &next };
        template.project(&p, .{ .anchor = "#section", .resource = bad });
        try std.testing.expect(html.failed);
    }
}

test "resource admission uses the same explicit scheme policy as bindings" {
    try std.testing.expect(gui.template.validExternalLink(.{ .value = "https://example.test" }));
    try std.testing.expect(!gui.template.validExternalLink(.{ .value = "http://example.test" }));
    try std.testing.expect(gui.template.validExternalLink(.{ .value = "http://example.test", .allow_http = true }));
    try std.testing.expect(!gui.template.validExternalLink(.{ .value = "http://u:p@example.test", .allow_http = true }));
}

test "typed input kind changes only the control attribute and retries output" {
    const template = @import("input_type").Scoped(.{ .first = 600, .count = 8 });
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [1]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &before };
    template.project(&p, .{ .kind = gui.template.InputType.password, .value = "draft" });
    try std.testing.expect(!html.failed);
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    html = .{ .buffer = bytes[0..1] };
    template.project(&p, .{ .kind = gui.template.InputType.text, .value = "draft" });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    next = .{};
    template.project(&p, .{ .kind = gui.template.InputType.text, .value = "draft" });
    try std.testing.expect(!html.failed and !scratch.failed);
    try std.testing.expectEqualStrings("A\t601\ttype\ttext\n", html.slice());
}

test "explicit object images admit blob sources, retain leaves and retry" {
    const template = @import("object_image").Scoped(.{ .first = 700, .count = 8 });
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [1]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &before };
    template.project(&p, .{ .source = @as(?[]const u8, null) });
    try std.testing.expect(!html.failed);
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    html = .{ .buffer = bytes[0..1] };
    template.project(&p, .{ .source = "blob:http://localhost:4173/example" });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    next = .{};
    template.project(&p, .{ .source = "blob:http://localhost:4173/example" });
    try std.testing.expect(!html.failed and !scratch.failed);
    try std.testing.expectEqualStrings("A\t701\tsrc\tblob:http://localhost:4173/example\n", html.slice());
    for ([_][]const u8{ "blob:null/example", "blob:javascript:evil", "blob:https://u:p@example.test/id", "data:image/png,abc", "blob:https://example.test/id\n" }) |bad| {
        html = .{ .buffer = &bytes };
        next = .{};
        p = .{ .html = &html, .next = &next };
        template.project(&p, .{ .source = bad });
        try std.testing.expect(html.failed);
    }
    html = .{ .buffer = &bytes };
    next = .{};
    p = .{ .html = &html, .next = &next };
    gui.template.attribute(&p, "src", .{ .node = 1, .value = "blob:http://localhost:4173/example" });
    try std.testing.expect(html.failed);
}

test "form metadata changes only named leaves and retries output" {
    const template = @import("form_metadata").Scoped(.{ .first = 600, .count = 8 });
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [1]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &before };
    template.project(&p, .{ .direction = "ltr", .name = "secret", .completion = @as(?[]const u8, "current-password") });
    try std.testing.expect(!html.failed);
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    html = .{ .buffer = bytes[0..1] };
    template.project(&p, .{ .direction = "rtl", .name = "key", .completion = @as(?[]const u8, null) });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    next = .{};
    template.project(&p, .{ .direction = "rtl", .name = "key", .completion = @as(?[]const u8, null) });
    try std.testing.expect(!html.failed and !scratch.failed);
    try std.testing.expectEqualStrings("A\t600\tdir\trtl\nA\t601\tname\tkey\nR\t601\tautocomplete\n", html.slice());
}

test "table spans patch cells only and retry output refusal" {
    const template = @import("table_spans");
    const Projection = gui.Projection(template.snapshot_capacity);
    var bytes: [2048]u8 = undefined;
    var scratch_bytes: [1]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = Projection.Snapshot{};
    var next = Projection.Snapshot{};
    var p = Projection{ .html = &html, .next = &before };
    template.project(&p, .{ .columns = @as(u8, 7), .rows = @as(?u8, 2), .draft = "Retained draft" });
    try std.testing.expect(!html.failed);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "colspan=\"7\"") != null);
    var writer = gui.patch.Writer{ .output = &html };
    p = .{ .html = &scratch, .next = &next, .previous = &before, .patches = &writer, .writing = false };
    html = .{ .buffer = bytes[0..1] };
    template.project(&p, .{ .columns = @as(u8, 6), .rows = @as(?u8, null), .draft = "Retained draft" });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    next = .{};
    template.project(&p, .{ .columns = @as(u8, 6), .rows = @as(?u8, null), .draft = "Retained draft" });
    try std.testing.expect(!html.failed and !scratch.failed);
    var expected: [128]u8 = undefined;
    try std.testing.expectEqualStrings(try std.fmt.bufPrint(&expected, "A\t{d}\tcolspan\t6\nR\t{d}\trowspan\n", .{ template.nodes.heading, template.nodes.cell }), html.slice());
}

test "nested keyed loops support static rendering, patches, outer context, and reordering" {
    const template = @import("nested_loop_fixture");
    const Item = struct { id: u32, title: []const u8 };
    const Category = struct { id: u32, name: []const u8, items: []const Item = &.{} };
    const Model = struct { categories: []const Category = &.{} };

    const cat_a_items: []const Item = &.{
        .{ .id = 1, .title = "Alpha Task" },
        .{ .id = 2, .title = "Beta Task" },
    };
    const cat_b_items: []const Item = &.{
        .{ .id = 10, .title = "Gamma Task" },
    };
    const initial_model = Model{
        .categories = &.{
            .{ .id = 100, .name = "Engineering", .items = cat_a_items },
            .{ .id = 200, .name = "Design", .items = cat_b_items },
        },
    };

    // 1. Static HTML rendering (Clean SSR)
    {
        var bytes: [4096]u8 = undefined;
        var w = gui.html.Writer{ .buffer = &bytes };
        template.renderHtml(&w, initial_model);
        try std.testing.expect(!w.failed);
        const html = w.slice();
        try std.testing.expect(std.mem.indexOf(u8, html, "<main") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "data-node-id") == null);
        try std.testing.expect(std.mem.indexOf(u8, html, "Engineering") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "<span>Alpha Task</span> in <span>Engineering</span>") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "<span>Beta Task</span> in <span>Engineering</span>") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "Design") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "<span>Gamma Task</span> in <span>Design</span>") != null);
    }

    // 2. Static HTML rendering with hydration node IDs (Hydrated SSR)
    {
        var bytes: [4096]u8 = undefined;
        var w = gui.html.Writer{ .buffer = &bytes };
        template.renderHtmlWithNodes(&w, initial_model);
        try std.testing.expect(!w.failed);
        const html = w.slice();
        try std.testing.expect(std.mem.indexOf(u8, html, "data-node-id=\"1\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "data-node-id=\"2\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "data-cat-id=\"100\"") != null);
        try std.testing.expect(std.mem.indexOf(u8, html, "data-item-id=\"1\"") != null);
    }

    // 3. Incremental WASM Projection and Patch Verification
    const Projection = gui.Projection(template.snapshot_capacity);
    var html_bytes: [8192]u8 = undefined;
    var patch_bytes: [8192]u8 = undefined;
    var initial_snapshot = Projection.Snapshot{};
    var next_snapshot = Projection.Snapshot{};

    // Initial full render
    var html = gui.html.Writer{ .buffer = &html_bytes };
    var p = Projection{ .html = &html, .next = &initial_snapshot };
    template.project(&p, initial_model);
    try std.testing.expect(!html.failed);
    try std.testing.expect(initial_snapshot.len > 0);

    // Verify all node IDs in initial snapshot are distinct
    for (initial_snapshot.entries[0..initial_snapshot.len], 0..) |entry, i| {
        for (initial_snapshot.entries[0..i]) |other| {
            if (entry.node == other.node and entry.property == other.property) {
                try std.testing.expect(false);
            }
        }
    }

    // 4. Patch: Reorder inner items within a category
    {
        var patch_writer = gui.html.Writer{ .buffer = &patch_bytes };
        var patches = gui.patch.Writer{ .output = &patch_writer };
        var scratch_bytes: [256]u8 = undefined;
        var scratch = gui.html.Writer{ .buffer = &scratch_bytes };

        const reordered_items: []const Item = &.{
            .{ .id = 2, .title = "Beta Task" },
            .{ .id = 1, .title = "Alpha Task" },
        };
        const reordered_model = Model{
            .categories = &.{
                .{ .id = 100, .name = "Engineering", .items = reordered_items },
                .{ .id = 200, .name = "Design", .items = cat_b_items },
            },
        };

        p = .{
            .html = &scratch,
            .next = &next_snapshot,
            .previous = &initial_snapshot,
            .patches = &patches,
            .writing = false,
        };
        template.project(&p, reordered_model);
        try std.testing.expect(!scratch.failed);
        const patch_str = patch_writer.slice();
        // Inner item move command emitted
        try std.testing.expect(std.mem.indexOf(u8, patch_str, "M\t") != null);
        // No full list replacement or deletion
        try std.testing.expect(std.mem.indexOf(u8, patch_str, "H\t") == null);
        try std.testing.expect(std.mem.indexOf(u8, patch_str, "D\t") == null);
    }

    // 5. Patch: Reorder outer categories (Engineering & Design swapped)
    {
        var patch_writer = gui.html.Writer{ .buffer = &patch_bytes };
        var patches = gui.patch.Writer{ .output = &patch_writer };
        var scratch_bytes: [256]u8 = undefined;
        var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
        var after_outer = Projection.Snapshot{};

        const swapped_model = Model{
            .categories = &.{
                .{ .id = 200, .name = "Design", .items = cat_b_items },
                .{ .id = 100, .name = "Engineering", .items = cat_a_items },
            },
        };

        p = .{
            .html = &scratch,
            .next = &after_outer,
            .previous = &initial_snapshot,
            .patches = &patches,
            .writing = false,
        };
        template.project(&p, swapped_model);
        try std.testing.expect(!scratch.failed);
        const patch_str = patch_writer.slice();
        // Outer category move command emitted
        try std.testing.expect(std.mem.indexOf(u8, patch_str, "M\t") != null);
        try std.testing.expect(std.mem.indexOf(u8, patch_str, "H\t") == null);
    }

    // 6. Patch: Update outer context and inner properties
    {
        var patch_writer = gui.html.Writer{ .buffer = &patch_bytes };
        var patches = gui.patch.Writer{ .output = &patch_writer };
        var scratch_bytes: [256]u8 = undefined;
        var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
        var after_rename = Projection.Snapshot{};

        const renamed_model = Model{
            .categories = &.{
                .{ .id = 100, .name = "Product Engineering", .items = cat_a_items },
                .{ .id = 200, .name = "Design", .items = cat_b_items },
            },
        };

        p = .{
            .html = &scratch,
            .next = &after_rename,
            .previous = &initial_snapshot,
            .patches = &patches,
            .writing = false,
        };
        template.project(&p, renamed_model);
        try std.testing.expect(!scratch.failed);
        const patch_str = patch_writer.slice();
        // Text changes emitted for both the category span and the inner spans referencing $outer.name
        try std.testing.expect(std.mem.indexOf(u8, patch_str, "Product Engineering") != null);
    }

    // 7. Admission limits: Rejecting excess rows or duplicates
    {
        // Exceeding inner limit (limit = 4, provide 5)
        const too_many_items: []const Item = &.{
            .{ .id = 1, .title = "A" },
            .{ .id = 2, .title = "B" },
            .{ .id = 3, .title = "C" },
            .{ .id = 4, .title = "D" },
            .{ .id = 5, .title = "E" },
        };
        var scratch_bytes: [256]u8 = undefined;
        var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
        var bad_snapshot = Projection.Snapshot{};
        p = Projection{ .html = &scratch, .next = &bad_snapshot };
        template.project(&p, Model{ .categories = &.{.{ .id = 1, .name = "Cat", .items = too_many_items }} });
        try std.testing.expect(scratch.failed);

        // Duplicate inner keys
        const duplicate_items: []const Item = &.{
            .{ .id = 1, .title = "A" },
            .{ .id = 1, .title = "B" },
        };
        scratch = gui.html.Writer{ .buffer = &scratch_bytes };
        bad_snapshot = .{};
        p = Projection{ .html = &scratch, .next = &bad_snapshot };
        template.project(&p, Model{ .categories = &.{.{ .id = 1, .name = "Cat", .items = duplicate_items }} });
        try std.testing.expect(scratch.failed);
    }
}

test "multiple selection and checkbox group array bindings synchronize state and emit patches" {
    const multi_select = @import("multi_select_fixture");
    const Projection = gui.Projection(multi_select.snapshot_capacity);

    const Option = struct { id: u32, value: []const u8, label: []const u8 };
    const ChannelAction = enum(u32) { update = 1 };
    const Model = struct {
        selected: []const []const u8,
        channel_input: ChannelAction = .update,
        options: []const Option,
    };

    const options: []const Option = &.{
        .{ .id = 1, .value = "email", .label = "Email notification" },
        .{ .id = 2, .value = "sms", .label = "SMS alert" },
        .{ .id = 3, .value = "push", .label = "Push notification" },
    };

    const initial_model = Model{
        .selected = &.{ "email", "sms" },
        .options = options,
    };

    // 1. Static HTML rendering
    var ssr_bytes: [2048]u8 = undefined;
    var ssr_writer = gui.html.Writer{ .buffer = &ssr_bytes };
    multi_select.renderHtml(&ssr_writer, initial_model);
    try std.testing.expect(!ssr_writer.failed);
    const ssr_clean = ssr_writer.slice();
    try std.testing.expect(std.mem.indexOf(u8, ssr_clean, "<select multiple") != null);
    try std.testing.expect(std.mem.indexOf(u8, ssr_clean, "data-select-values=\"email\x1fsms\"") != null);
    // email and sms checkboxes are checked, push is not
    try std.testing.expect(std.mem.indexOf(u8, ssr_clean, "<input type=\"checkbox\" value=\"email\" data-input-kind=\"1\" checked") != null);
    try std.testing.expect(std.mem.indexOf(u8, ssr_clean, "<input type=\"checkbox\" value=\"sms\" data-input-kind=\"1\" checked") != null);
    try std.testing.expect(std.mem.indexOf(u8, ssr_clean, "<input type=\"checkbox\" value=\"push\" data-input-kind=\"1\" checked") == null);
    try std.testing.expect(std.mem.indexOf(u8, ssr_clean, "<input type=\"checkbox\" value=\"push\" data-input-kind=\"1\" data-value-format=\"checked\">") != null);

    // 2. Full WASM initial projection
    var full_bytes: [2048]u8 = undefined;
    var full_writer = gui.html.Writer{ .buffer = &full_bytes };
    var initial_snapshot = Projection.Snapshot{};
    var p = Projection{ .html = &full_writer, .next = &initial_snapshot, .writing = true };
    multi_select.project(&p, initial_model);
    try std.testing.expect(!full_writer.failed);
    const full_output = full_writer.slice();
    try std.testing.expect(std.mem.indexOf(u8, full_output, "data-select-values=\"email\x1fsms\"") != null);

    // 3. Patch projection: Deselecting sms and selecting push
    var patch_bytes: [2048]u8 = undefined;
    var patch_writer = gui.html.Writer{ .buffer = &patch_bytes };
    var patches = gui.patch.Writer{ .output = &patch_writer };
    var scratch_bytes: [256]u8 = undefined;
    var scratch = gui.html.Writer{ .buffer = &scratch_bytes };
    var after_snapshot = Projection.Snapshot{};

    const updated_model = Model{
        .selected = &.{ "email", "push" },
        .options = options,
    };

    p = .{
        .html = &scratch,
        .next = &after_snapshot,
        .previous = &initial_snapshot,
        .patches = &patches,
        .writing = false,
    };
    multi_select.project(&p, updated_model);
    try std.testing.expect(!scratch.failed);
    const patch_output = patch_writer.slice();

    // Attribute update on select for data-select-values
    try std.testing.expect(std.mem.indexOf(u8, patch_output, "A\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, patch_output, "data-select-values") != null);
    // Checkbox patches: sms becomes false, push becomes true
    try std.testing.expect(std.mem.indexOf(u8, patch_output, "C\t") != null);
}
