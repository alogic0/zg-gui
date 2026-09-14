//! Explicit Zig-owned leaves shared by initial projections and typed patches.
//! No HTML parsing or tree diffing: callers name every leaf and list membership key.
const std = @import("std");
const Html = @import("html.zig").Writer;
const patch = @import("patch.zig");

const Entry = struct { node: u32, property: u64, value: u64 };
const Change = struct { node: u32, property: []const u8, value: ?[]const u8 };
// Snapshot capacity changes storage, not comparison semantics. Keep hashing and
// lookup in one implementation instead of duplicating it for every capacity.
noinline fn recordChange(input: struct { next: []Entry, len: *usize, previous: []const Entry, failed: *bool, change: Change }) bool {
    const change = input.change;
    const entry = Entry{ .node = change.node, .property = std.hash.Wyhash.hash(0, change.property), .value = if (change.value) |v| std.hash.Wyhash.hash(1, v) else 0 };
    if (input.len.* == input.next.len) {
        input.failed.* = true;
        return false;
    }
    input.next[input.len.*] = entry;
    input.len.* += 1;
    for (input.previous) |old| {
        if (old.node == change.node and old.property == entry.property) return old.value != entry.value;
    }
    return true;
}

pub fn Projection(comptime capacity: usize) type {
    return struct {
        const Self = @This();
        pub const Snapshot = struct { entries: [capacity]Entry = undefined, len: usize = 0 };
        pub const List = struct { node: u32, start: usize, writing: bool, replace: bool };
        pub const Child = struct { owner: u32, start: usize, writing: bool, append: bool };
        html: *Html,
        patches: ?*patch.Writer = null,
        previous: ?*const Snapshot = null,
        next: *Snapshot,
        writing: bool = true,

        fn changed(self: *Self, input: Change) bool {
            return recordChange(.{ .next = &self.next.entries, .len = &self.next.len, .previous = if (self.previous) |previous| previous.entries[0..previous.len] else &.{}, .failed = &self.html.failed, .change = input });
        }
        pub fn add(self: *Self, value: []const u8) void {
            if (self.writing) self.html.add(value);
        }
        pub fn print(self: *Self, comptime format: []const u8, args: anytype) void {
            if (self.writing) self.html.print(format, args);
        }
        pub fn escaped(self: *Self, value: []const u8) void {
            if (self.writing) self.html.escaped(value);
        }
        pub fn node(self: *Self, id: u32) void {
            self.print(" data-node-id=\"{d}\"", .{id});
        }
        pub fn attr(self: *Self, input: struct { node: u32, name: []const u8, value: ?[]const u8 }) void {
            const dirty = self.changed(.{ .node = input.node, .property = input.name, .value = input.value });
            if (self.writing) {
                if (input.value) |value| {
                    self.print(" {s}=\"", .{input.name});
                    self.escaped(value);
                    self.add("\"");
                }
            } else if (dirty) if (self.patches) |writer| {
                if (input.value) |value| writer.attribute(.{ .node = input.node, .name = input.name, .value = value }) else writer.removeAttribute(.{ .node = input.node, .name = input.name });
            };
        }
        pub fn visible(self: *Self, input: struct { node: u32, value: bool }) void {
            const id = input.node;
            const value = input.value;
            self.attr(.{ .node = id, .name = "hidden", .value = if (value) null else "" });
        }
        pub fn text(self: *Self, input: struct { node: u32, value: []const u8 }) void {
            const id = input.node;
            const value = input.value;
            const dirty = self.changed(.{ .node = id, .property = "#text", .value = value });
            if (self.writing) self.escaped(value) else if (dirty) if (self.patches) |writer| writer.text(.{ .node = id, .value = value });
        }
        pub fn textElement(self: *Self, comptime tag: []const u8, input: struct { node: u32, value: []const u8 }) void {
            const id = input.node;
            const value = input.value;
            self.add("<" ++ tag);
            self.node(id);
            self.add(">");
            self.text(.{ .node = id, .value = value });
            self.add("</" ++ tag ++ ">");
        }
        pub fn formValue(self: *Self, input: struct { node: u32, text_value: []const u8 }) void {
            const id = input.node;
            const text_value = input.text_value;
            const dirty = self.changed(.{ .node = id, .property = "#value", .value = text_value });
            if (self.writing) {
                self.add(" value=\"");
                self.escaped(text_value);
                self.add("\"");
            } else if (dirty) if (self.patches) |writer| writer.formValue(.{ .node = id, .value = text_value });
        }
        /// A domain revision names a new focus request, so later render passes
        /// never steal focus back from the user's current control.
        pub fn focus(self: *Self, input: struct { owner: u32, target: ?u32, revision: u32 }) void {
            var value: [16]u8 = undefined;
            const dirty = self.changed(.{ .node = input.owner, .property = "#focus", .value = std.fmt.bufPrint(&value, "{d}", .{input.revision}) catch unreachable });
            if (dirty and !self.writing and input.revision > 0) if (input.target) |target| if (self.patches) |writer| writer.focus(.{ .node = target, .mode = .nearest });
        }
        pub fn checked(self: *Self, input: struct { node: u32, value: bool }) void {
            const id = input.node;
            const value = input.value;
            const dirty = self.changed(.{ .node = id, .property = "#checked", .value = if (value) "true" else "false" });
            if (self.writing) {
                if (value) self.add(" checked");
            } else if (dirty) if (self.patches) |writer| writer.checked(.{ .node = id, .value = value });
        }
        pub fn selectedValue(self: *Self, input: struct { node: u32, value: []const u8 }) void {
            const id = input.node;
            const value = input.value;
            const dirty = self.changed(.{ .node = id, .property = "#value", .value = value });
            if (!self.writing and dirty) if (self.patches) |writer| writer.formValue(.{ .node = id, .value = value });
        }
        pub fn textareaValue(self: *Self, input: struct { node: u32, value: []const u8 }) void {
            const id = input.node;
            const value = input.value;
            const dirty = self.changed(.{ .node = id, .property = "#value", .value = value });
            if (self.writing) self.escaped(value) else if (dirty) if (self.patches) |writer| writer.formValue(.{ .node = id, .value = value });
        }
        /// Call inside the stable child-list element, with a domain membership key.
        /// Descendant patches are suppressed when this list introduces their nodes.
        pub fn beginList(self: *Self, input: struct { node: u32, membership: []const u8 }) List {
            const id = input.node;
            const membership = input.membership;
            const dirty = self.changed(.{ .node = id, .property = "#children", .value = membership });
            const list = List{ .node = id, .start = self.html.len, .writing = self.writing, .replace = !self.writing and self.patches != null and dirty };
            if (list.replace) self.writing = true;
            return list;
        }
        pub fn endList(self: *Self, list: List) void {
            self.writing = list.writing;
            if (list.replace) {
                self.patches.?.html(.{ .node = list.node, .value = self.html.slice()[list.start..] });
                self.html.len = list.start;
            }
        }
        /// Reconcile explicitly named children without replacing retained rows.
        /// Project each child with beginChild/endChild, then declare its order.
        pub fn keyedList(self: *Self, input: struct { owner: u32, nodes: []const u32 }) void {
            if (self.writing) return;
            const writer = self.patches orelse return;
            const previous = self.previous orelse return;
            const property = std.hash.Wyhash.hash(0, "#parent");
            const parent = std.hash.Wyhash.hash(1, std.mem.asBytes(&input.owner));
            for (previous.entries[0..previous.len]) |entry| {
                if (entry.property == property and entry.value == parent and
                    std.mem.indexOfScalar(u32, input.nodes, entry.node) == null)
                    writer.remove(entry.node);
            }
        }
        pub fn beginChild(self: *Self, input: struct { owner: u32, node: u32 }) Child {
            const added = self.changed(.{ .node = input.node, .property = "#parent", .value = std.mem.asBytes(&input.owner) });
            const child = Child{ .owner = input.owner, .start = self.html.len, .writing = self.writing, .append = !self.writing and self.patches != null and added };
            if (child.append) self.writing = true;
            return child;
        }
        pub fn endChild(self: *Self, child: Child) void {
            self.writing = child.writing;
            if (child.append) {
                self.patches.?.appendHtml(.{ .node = child.owner, .value = self.html.slice()[child.start..] });
                self.html.len = child.start;
            }
        }
        /// All nodes must already be children of owner. Reorder their existing
        /// DOM objects without replacing the list or any row controls.
        pub fn order(self: *Self, input: struct { owner: u32, nodes: []const u32 }) void {
            const dirty = self.changed(.{ .node = input.owner, .property = "#order", .value = std.mem.sliceAsBytes(input.nodes) });
            if (!dirty or self.writing or input.nodes.len < 2) return;
            if (self.patches) |writer| for (input.nodes[1..], 0..) |node_id, i| {
                writer.move(.{ .node = node_id, .sibling = input.nodes[i], .placement = .after });
            };
        }
    };
}

pub fn boolean(value: bool) []const u8 {
    return if (value) "true" else "false";
}

test "structural owners introduce descendants once and leaf changes never replace ancestors" {
    const P = Projection(8);
    var scratch_buffer: [1024]u8 = undefined;
    var output_buffer: [1024]u8 = undefined;
    var html = Html{ .buffer = &scratch_buffer };
    var output = Html{ .buffer = &output_buffer };
    var writer = patch.Writer{ .output = &output };
    var empty = P.Snapshot{};
    var mounted = P.Snapshot{};
    var p = P{ .html = &html, .patches = &writer, .previous = &empty, .next = &mounted, .writing = false };
    const list = p.beginList(.{ .node = 1, .membership = "item-42" });
    p.textElement("span", .{ .node = 2, .value = "one" });
    p.endList(list);
    try std.testing.expectEqualStrings("H\t1\t\"<span data-node-id=\\\"2\\\">one</span>\"\n", output.slice());
    output.len = 0;
    var updated = P.Snapshot{};
    p.previous = &mounted;
    p.next = &updated;
    const retained = p.beginList(.{ .node = 1, .membership = "item-42" });
    p.textElement("span", .{ .node = 2, .value = "two" });
    p.endList(retained);
    try std.testing.expectEqualStrings("T\t2\t\"two\"\n", output.slice());
    output.len = 0;
    var repeated = P.Snapshot{};
    p.previous = &updated;
    p.next = &repeated;
    const same = p.beginList(.{ .node = 1, .membership = "item-42" });
    p.textElement("span", .{ .node = 2, .value = "two" });
    p.endList(same);
    try std.testing.expectEqual(@as(usize, 0), output.len);
}

test "keyed child membership preserves retained rows and suppresses absent descendant patches" {
    const P = Projection(16);
    const Row = struct {
        fn project(p: *P, nodes: []const u32, text: []const u8) void {
            p.keyedList(.{ .owner = 1, .nodes = nodes });
            for (nodes) |node| {
                const child = p.beginChild(.{ .owner = 1, .node = node });
                p.add("<li");
                p.node(node);
                p.add(">");
                p.text(.{ .node = node, .value = text });
                p.add("</li>");
                p.endChild(child);
            }
            p.order(.{ .owner = 1, .nodes = nodes });
        }
    };
    var scratch_bytes: [2048]u8 = undefined;
    var output_bytes: [2048]u8 = undefined;
    var scratch = Html{ .buffer = &scratch_bytes };
    var output = Html{ .buffer = &output_bytes };
    var writer = patch.Writer{ .output = &output };
    var initial = P.Snapshot{};
    var p = P{ .html = &scratch, .next = &initial };
    Row.project(&p, &.{ 2, 3 }, "before");
    scratch.len = 0;
    var changed = P.Snapshot{};
    p = .{ .html = &scratch, .patches = &writer, .previous = &initial, .next = &changed, .writing = false };
    Row.project(&p, &.{ 3, 4 }, "after");
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "D\t2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "T\t3\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "J\t1\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "T\t4\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "D\t3\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "H\t") == null);
    try std.testing.expect(!scratch.failed and !output.failed);
    output.len = 0;
    var repeated = P.Snapshot{};
    p.previous = &changed;
    p.next = &repeated;
    Row.project(&p, &.{ 3, 4 }, "after");
    try std.testing.expectEqual(@as(usize, 0), output.len);
    // A newly introduced parent owns its children; append/remove/leaf commands
    // must not separately target descendants before that parent is installed.
    var mounted = P.Snapshot{};
    p.previous = &repeated;
    p.next = &mounted;
    const parent = p.beginList(.{ .node = 1, .membership = "new-parent" });
    Row.project(&p, &.{5}, "new");
    p.endList(parent);
    try std.testing.expect(std.mem.startsWith(u8, output.slice(), "H\t1\t"));
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "J\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "D\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "T\t") == null);
}
