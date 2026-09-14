//! Typed DOM command protocol. Node IDs and UI state belong to consumers.
const std = @import("std");
const Html = @import("html.zig").Writer;

pub const RenderMode = enum(u32) { full = 0, patch = 1 };
pub const Value = struct { node: u32, value: []const u8 };
pub const Attribute = struct { node: u32, name: []const u8, value: []const u8 };
pub const Boolean = struct { node: u32, value: bool };
pub const Placement = enum { before, after };
pub const FocusMode = enum { preserve_scroll, nearest, end };

pub const Range = struct {
    base: u32,
    count: u32,

    pub fn id(self: Range, index: usize) error{InvalidNodeId}!u32 {
        if (index >= self.count or index > std.math.maxInt(u32) - self.base)
            return error.InvalidNodeId;
        return self.base + @as(u32, @intCast(index));
    }
};

pub const Writer = struct {
    output: *Html,

    pub const Attributes = struct {
        class_name: ?[]const u8 = null,
        aria_expanded: ?bool = null,
        aria_pressed: ?bool = null,
        aria_checked: ?bool = null,
        aria_busy: ?bool = null,
        aria_label: ?[]const u8 = null,
    };

    pub fn attribute(self: *Writer, input: Attribute) void {
        if (input.name.len == 0 or std.mem.indexOfAny(u8, input.name, "\t\r\n") != null) {
            self.output.failed = true;
            return;
        }
        self.output.print("A\t{d}\t{s}\t", .{ input.node, input.name });
        for (input.value) |byte| self.output.add(switch (byte) {
            '\t', '\r', '\n' => " ",
            else => &.{byte},
        });
        self.output.add("\n");
    }

    pub fn removeAttribute(self: *Writer, input: struct { node: u32, name: []const u8 }) void {
        if (input.name.len == 0 or std.mem.indexOfAny(u8, input.name, "\t\r\n") != null) {
            self.output.failed = true;
            return;
        }
        self.output.print("R\t{d}\t{s}\n", .{ input.node, input.name });
    }

    pub fn set(self: *Writer, input: struct { node: u32, attributes: Attributes }) void {
        inline for (.{ .{ "class_name", "class" }, .{ "aria_label", "aria-label" } }) |pair| {
            if (@field(input.attributes, pair[0])) |v| self.attribute(.{ .node = input.node, .name = pair[1], .value = v });
        }
        inline for (.{ .{ "aria_expanded", "aria-expanded" }, .{ "aria_pressed", "aria-pressed" }, .{ "aria_checked", "aria-checked" }, .{ "aria_busy", "aria-busy" } }) |pair| {
            if (@field(input.attributes, pair[0])) |v| self.attribute(.{ .node = input.node, .name = pair[1], .value = if (v) "true" else "false" });
        }
    }

    pub fn visible(self: *Writer, input: Boolean) void {
        if (input.value) self.removeAttribute(.{ .node = input.node, .name = "hidden" }) else self.attribute(.{ .node = input.node, .name = "hidden", .value = "" });
    }

    pub fn text(self: *Writer, input: Value) void {
        self.stringCommand(.{ .operation = 'T', .input = input });
    }
    pub fn formValue(self: *Writer, input: Value) void {
        self.stringCommand(.{ .operation = 'V', .input = input });
    }
    pub fn html(self: *Writer, input: Value) void {
        self.stringCommand(.{ .operation = 'H', .input = input });
    }
    pub fn appendHtml(self: *Writer, input: Value) void {
        self.stringCommand(.{ .operation = 'J', .input = input });
    }
    pub fn checked(self: *Writer, input: Boolean) void {
        self.output.print("C\t{d}\t{s}\n", .{ input.node, if (input.value) "true" else "false" });
    }
    pub fn focus(self: *Writer, input: struct { node: u32, mode: FocusMode = .preserve_scroll }) void {
        self.output.print("F\t{d}{s}\n", .{ input.node, switch (input.mode) {
            .preserve_scroll => "",
            .nearest => "\tnearest",
            .end => "\tend",
        } });
    }
    pub fn move(self: *Writer, input: struct { node: u32, sibling: u32, placement: Placement }) void {
        self.output.print("M\t{d}\t{d}\t{s}\n", .{ input.node, input.sibling, @tagName(input.placement) });
    }
    pub fn remove(self: *Writer, node: u32) void {
        self.output.print("D\t{d}\n", .{node});
    }

    fn stringCommand(self: *Writer, command: struct { operation: u8, input: Value }) void {
        self.output.print("{c}\t{d}\t", .{ command.operation, command.input.node });
        self.jsonString(command.input.value);
        self.output.add("\n");
    }

    fn jsonString(self: *Writer, value: []const u8) void {
        const hex = "0123456789abcdef";
        self.output.add("\"");
        for (value) |byte| switch (byte) {
            '"' => self.output.add("\\\""),
            '\\' => self.output.add("\\\\"),
            '\n' => self.output.add("\\n"),
            '\r' => self.output.add("\\r"),
            '\t' => self.output.add("\\t"),
            0...8, 11, 12, 14...31 => {
                const escaped = [_]u8{ '\\', 'u', '0', '0', hex[byte >> 4], hex[byte & 0x0f] };
                self.output.add(&escaped);
            },
            else => self.output.add(&.{byte}),
        };
        self.output.add("\"");
    }
};

test "text round trips JSON controls without changing the line protocol" {
    var bytes: [512]u8 = undefined;
    var html = Html{ .buffer = &bytes };
    var p = Writer{ .output = &html };
    var controls: [32]u8 = undefined;
    for (&controls, 0..) |*byte, i| byte.* = @intCast(i);
    p.text(.{ .node = 7, .value = &controls });
    try std.testing.expect(!html.failed);
    const raw = html.slice();
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, raw, "\n"));
    const parsed = try std.json.parseFromSlice([]const u8, std.testing.allocator, raw[4 .. raw.len - 1], .{});
    defer parsed.deinit();
    try std.testing.expectEqualSlices(u8, &controls, parsed.value);
}

test "overflow and invalid attribute names reject publication" {
    var bytes: [8]u8 = undefined;
    var html = Html{ .buffer = &bytes };
    var p = Writer{ .output = &html };
    p.text(.{ .node = 1, .value = "too long" });
    try std.testing.expect(html.failed);
    html = .{ .buffer = &bytes };
    p.attribute(.{ .node = 1, .name = "x\nT", .value = "" });
    try std.testing.expect(html.failed);
    try std.testing.expectEqual(@as(usize, 0), html.len);
}

test "ranges reject out of bounds and integer overflow" {
    try std.testing.expectEqual(@as(u32, 11), try (Range{ .base = 10, .count = 2 }).id(1));
    try std.testing.expectError(error.InvalidNodeId, (Range{ .base = 10, .count = 2 }).id(2));
    try std.testing.expectError(error.InvalidNodeId, (Range{ .base = std.math.maxInt(u32), .count = 2 }).id(1));
}

test "named state commands cover accessibility values and focus modes" {
    var bytes: [1024]u8 = undefined;
    var html = Html{ .buffer = &bytes };
    var p = Writer{ .output = &html };
    p.set(.{ .node = 7, .attributes = .{ .class_name = "active", .aria_expanded = true, .aria_pressed = false, .aria_checked = false, .aria_busy = true, .aria_label = "one\ntwo" } });
    p.visible(.{ .node = 8, .value = false });
    p.visible(.{ .node = 8, .value = true });
    p.focus(.{ .node = 9 });
    p.focus(.{ .node = 9, .mode = .nearest });
    p.focus(.{ .node = 9, .mode = .end });
    try std.testing.expect(!html.failed);
    try std.testing.expectEqualStrings(
        "A\t7\tclass\tactive\nA\t7\taria-label\tone two\n" ++
            "A\t7\taria-expanded\ttrue\nA\t7\taria-pressed\tfalse\n" ++
            "A\t7\taria-checked\tfalse\nA\t7\taria-busy\ttrue\n" ++
            "A\t8\thidden\t\nR\t8\thidden\nF\t9\nF\t9\tnearest\nF\t9\tend\n",
        html.slice(),
    );
}
