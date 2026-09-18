//! Copyable bounded property snapshots with an intrusive hash-bucket index.
const std = @import("std");

pub const Entry = struct { node: u32, link: u32, property: u64, value: u64 };
pub const Change = struct { node: u32, property: []const u8, value: ?[]const u8 };
pub const View = struct { entries: []const Entry, buckets: []const u32 };

fn bucket(input: struct { node: u32, property: u64, count: usize }) usize {
    const key = input.property ^ (@as(u64, input.node) *% 0x9e3779b97f4a7c15);
    return @as(usize, @truncate(key ^ (key >> 32))) & (input.count - 1);
}

/// Capacity changes storage only; hashing and lookup share this implementation.
pub noinline fn record(input: struct {
    entries: []Entry,
    buckets: []u32,
    len: *usize,
    previous: ?View,
    change: Change,
}) error{SnapshotTooLarge}!bool {
    if (input.len.* == input.entries.len) return error.SnapshotTooLarge;
    const change = input.change;
    const property = std.hash.Wyhash.hash(0, change.property);
    const value = if (change.value) |v| std.hash.Wyhash.hash(1, v) else 0;
    const slot = bucket(.{ .node = change.node, .property = property, .count = input.buckets.len });
    input.entries[input.len.*] = .{ .node = change.node, .property = property, .value = value, .link = input.buckets[slot] };
    input.len.* += 1;
    input.buckets[slot] = @intCast(input.len.*);
    var changed = true;
    if (input.previous) |old| {
        var cursor = old.buckets[bucket(.{ .node = change.node, .property = property, .count = old.buckets.len })];
        while (cursor != 0) {
            const entry = old.entries[cursor - 1];
            // Chains run newest to oldest: the first recorded matching key wins.
            if (entry.node == change.node and entry.property == property) changed = entry.value != value;
            cursor = entry.link;
        }
    }
    return changed;
}

pub fn Snapshot(comptime capacity: usize) type {
    if (capacity > std.math.maxInt(u32)) @compileError("snapshot capacity exceeds index representation");
    const bucket_count = comptime blk: {
        var count: usize = 1;
        while (count < (capacity + 3) / 4) count *= 2;
        break :blk count;
    };
    return struct {
        const Self = @This();
        entries: [capacity]Entry = undefined,
        buckets: [bucket_count]u32 = @splat(0),
        len: usize = 0,

        pub fn view(self: *const Self) View {
            return .{ .entries = self.entries[0..self.len], .buckets = &self.buckets };
        }
        pub fn changed(self: *Self, input: struct { previous: ?*const Self, change: Change }) error{SnapshotTooLarge}!bool {
            return record(.{ .entries = &self.entries, .buckets = &self.buckets, .len = &self.len, .previous = if (input.previous) |old| old.view() else null, .change = input.change });
        }
    };
}

test "indexed snapshots preserve reordering conditional keys collisions and properties" {
    const S = Snapshot(64);
    var previous = S{};
    for (0..64) |i| _ = try previous.changed(.{ .previous = null, .change = .{
        .node = @intCast(i / 2 + 1),
        .property = if (i % 2 == 0) "text" else "class",
        .value = "before",
    } });
    const copy = previous;
    previous = .{}; // The copy owns its index; no references into the old value.
    var next = S{};
    for (0..64) |i| {
        const n = 63 - i;
        try std.testing.expectEqual(n == 17, try next.changed(.{ .previous = &copy, .change = .{
            .node = @intCast(n / 2 + 1),
            .property = if (n % 2 == 0) "text" else "class",
            .value = if (n == 17) "after" else "before",
        } }));
    }
    try std.testing.expectError(error.SnapshotTooLarge, next.changed(.{ .previous = &copy, .change = .{ .node = 99, .property = "text", .value = null } }));
    try std.testing.expectEqual(@as(usize, 64), next.len);
    var removed = S{};
    _ = try removed.changed(.{ .previous = &next, .change = .{ .node = 32, .property = "text", .value = "before" } });
    var restored = S{};
    try std.testing.expect(try restored.changed(.{ .previous = &removed, .change = .{ .node = 1, .property = "text", .value = "before" } }));
    try std.testing.expect(!try restored.changed(.{ .previous = &removed, .change = .{ .node = 32, .property = "text", .value = "before" } }));
}

test "indexed snapshots retain first occurrence semantics and empty capacity" {
    var old = Snapshot(4){}; // One bucket forces every key to collide.
    for ([_][]const u8{ "first", "second" }) |v| _ = try old.changed(.{ .previous = null, .change = .{ .node = 7, .property = "text", .value = v } });
    var next = Snapshot(4){};
    try std.testing.expect(!try next.changed(.{ .previous = &old, .change = .{ .node = 7, .property = "text", .value = "first" } }));
    try std.testing.expect(try next.changed(.{ .previous = &old, .change = .{ .node = 7, .property = "class", .value = "first" } }));
    var empty = Snapshot(0){};
    try std.testing.expectError(error.SnapshotTooLarge, empty.changed(.{ .previous = null, .change = .{ .node = 1, .property = "text", .value = null } }));
}
