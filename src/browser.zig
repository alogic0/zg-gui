//! Finite post-projection browser requests. All storage belongs to the caller.
const std = @import("std");
const Html = @import("html.zig").Writer;
pub const FocusMode = @import("patch.zig").FocusMode;
pub const Scheme = enum { light, dark };
pub const Guard = enum { always, if_body };
pub const max_bytes = 4096;
pub const max_requests = 16;

pub const Writer = struct {
    const Kind = enum { dialog, focus, scroll, scheme, frame, preferences };
    const Identity = struct { kind: Kind, owner: u32 };
    output: *Html,
    count: usize = 0,
    finished: bool = false,
    identities: [max_requests]Identity = undefined,

    pub fn init(output: *Html) Writer {
        output.add("[");
        return .{ .output = output };
    }
    fn request(self: *Writer, value: anytype) void {
        if (self.finished or self.count == max_requests) {
            self.output.failed = true;
            return;
        }
        const identity = Identity{ .kind = comptime std.meta.stringToEnum(Kind, value.kind).?, .owner = if (@hasField(@TypeOf(value), "owner")) value.owner else if (@hasField(@TypeOf(value), "node")) value.node else 0 };
        for (self.identities[0..self.count]) |old| if (std.meta.eql(old, identity)) {
            self.output.failed = true;
            return;
        };
        self.identities[self.count] = identity;
        if (self.count > 0) self.output.add(",");
        self.count += 1;
        var stream = self.output.openStream();
        std.json.Stringify.value(value, .{}, &stream.writer) catch {
            self.output.failed = true;
        };
        stream.finish();
        if (self.output.len > max_bytes) self.output.failed = true;
    }
    fn positive(self: *Writer, value: u32) bool {
        if (value == 0) self.output.failed = true;
        return value > 0;
    }
    fn key(self: *Writer, value: []const u8) bool {
        if (value.len == 0 or value.len > 128) {
            self.output.failed = true;
            return false;
        }
        for (value) |c| if (!(std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.')) {
            self.output.failed = true;
            return false;
        };
        return true;
    }
    pub fn dialog(self: *Writer, input: struct { node: u32, open: bool, cancel: u32, revision: u32 = 0 }) void {
        if (!self.positive(input.node) or !self.positive(input.cancel)) return;
        if (input.open and !self.positive(input.revision)) return;
        self.request(.{ .kind = "dialog", .node = input.node, .open = input.open, .cancel = input.cancel, .revision = input.revision });
    }
    pub fn focus(self: *Writer, input: struct { owner: u32, node: u32, revision: u32, mode: FocusMode = .preserve_scroll, guard: Guard = .always }) void {
        if (!self.positive(input.owner) or !self.positive(input.node) or !self.positive(input.revision)) return;
        self.request(.{ .kind = "focus", .owner = input.owner, .node = input.node, .revision = input.revision, .mode = input.mode, .guard = input.guard });
    }
    pub fn scroll(self: *Writer, input: struct { owner: u32, revision: u32, x: u32 = 0, y: u32 = 0 }) void {
        if (!self.positive(input.owner) or !self.positive(input.revision)) return;
        if (input.x > 16777216 or input.y > 16777216) {
            self.output.failed = true;
            return;
        }
        self.request(.{ .kind = "scroll", .owner = input.owner, .revision = input.revision, .x = input.x, .y = input.y });
    }
    pub fn scheme(self: *Writer, input: struct { value: Scheme, key: []const u8, revision: u32 = 0 }) void {
        if (!self.key(input.key)) return;
        self.request(.{ .kind = "scheme", .value = input.value, .key = input.key, .revision = input.revision });
    }
    pub fn frame(self: *Writer, input: struct { owner: u32, revision: u32, event: u32 }) void {
        if (!self.positive(input.owner) or !self.positive(input.revision) or !self.positive(input.event)) return;
        self.request(.{ .kind = "frame", .owner = input.owner, .revision = input.revision, .event = input.event });
    }
    pub fn preferences(self: *Writer, input: struct { owner: u32, event: u32, key: []const u8 }) void {
        if (!self.positive(input.owner) or !self.positive(input.event) or !self.key(input.key)) return;
        self.request(.{ .kind = "preferences", .owner = input.owner, .event = input.event, .key = input.key });
    }
    pub fn finish(self: *Writer) void {
        if (self.finished) {
            self.output.failed = true;
            return;
        }
        self.output.add("]");
        self.finished = true;
        if (self.output.len > max_bytes) self.output.failed = true;
    }
};

test "browser requests serialize finite state and reject invalid candidates" {
    var bytes: [max_bytes]u8 = undefined;
    var output = Html{ .buffer = &bytes };
    var writer = Writer.init(&output);
    writer.dialog(.{ .node = 4, .open = true, .cancel = 2, .revision = 1 });
    writer.focus(.{ .owner = 1, .node = 5, .revision = 1, .guard = .if_body });
    writer.frame(.{ .owner = 1, .revision = 7, .event = 1 });
    writer.preferences(.{ .owner = 2, .event = 3, .key = "appearance" });
    writer.scheme(.{ .value = .dark, .key = "appearance", .revision = 1 });
    writer.scroll(.{ .owner = 1, .revision = 1 });
    writer.finish();
    try std.testing.expect(!output.failed);
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.slice(), .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 6), parsed.value.array.items.len);
    output = .{ .buffer = &bytes };
    writer = Writer.init(&output);
    writer.scheme(.{ .value = .light, .key = "bad key" });
    try std.testing.expect(output.failed);
    output = .{ .buffer = &bytes };
    writer = Writer.init(&output);
    writer.frame(.{ .owner = 0, .revision = 1, .event = 1 });
    try std.testing.expect(output.failed);
    output = .{ .buffer = &bytes };
    writer = Writer.init(&output);
    writer.frame(.{ .owner = 1, .revision = 1, .event = 1 });
    writer.frame(.{ .owner = 1, .revision = 2, .event = 1 });
    try std.testing.expect(output.failed);
}
test "browser request capacity failure is isolated to caller candidate storage" {
    var tiny: [12]u8 = undefined;
    var output = Html{ .buffer = &tiny };
    var writer = Writer.init(&output);
    writer.dialog(.{ .node = 1, .open = true, .cancel = 1, .revision = 1 });
    writer.finish();
    try std.testing.expect(output.failed);
    var bytes: [max_bytes]u8 = undefined;
    output = .{ .buffer = &bytes };
    writer = Writer.init(&output);
    for (0..max_requests + 1) |i| writer.frame(.{ .owner = @intCast(i + 1), .revision = 1, .event = 1 });
    writer.finish();
    try std.testing.expect(output.failed);
    output = .{ .buffer = &bytes };
    writer = Writer.init(&output);
    writer.frame(.{ .owner = 1, .revision = 1, .event = 1 });
    writer.finish();
    try std.testing.expect(!output.failed);
}
