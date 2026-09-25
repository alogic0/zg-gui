//! Zero-allocation stable dense index mapping for arbitrary external identifiers.
const std = @import("std");

fn keysEqual(comptime T: type, a: T, b: T) bool {
    return switch (@typeInfo(T)) {
        .pointer => |p| switch (p.size) {
            .slice => if (p.child == u8) std.mem.eql(u8, a, b) else std.mem.eql(p.child, a, b),
            else => a == b,
        },
        .array => |arr| if (arr.child == u8) std.mem.eql(u8, &a, &b) else std.mem.eql(arr.child, &a, &b),
        else => a == b,
    };
}

/// Generic compact key registry for value types, borrowed slices, and fixed arrays.
pub fn CompactKeyRegistry(comptime KeyType: type, comptime capacity: usize) type {
    if (capacity == 0 or capacity > std.math.maxInt(u32)) {
        @compileError("CompactKeyRegistry capacity must be between 1 and 2^32-1");
    }
    return struct {
        const Self = @This();

        entries: [capacity]?KeyType = @splat(null),
        active_count: usize = 0,

        pub fn get(self: *const Self, key: KeyType) ?u32 {
            for (self.entries[0..], 0..) |entry, i| {
                if (entry) |k| {
                    if (keysEqual(KeyType, k, key)) return @intCast(i);
                }
            }
            return null;
        }

        pub fn getOrAssign(self: *Self, key: KeyType) error{CapacityExceeded}!u32 {
            if (self.get(key)) |slot| return slot;
            for (&self.entries, 0..) |*entry, i| {
                if (entry.* == null) {
                    entry.* = key;
                    self.active_count += 1;
                    return @intCast(i);
                }
            }
            return error.CapacityExceeded;
        }

        pub fn release(self: *Self, key: KeyType) bool {
            for (&self.entries) |*entry| {
                if (entry.*) |k| {
                    if (keysEqual(KeyType, k, key)) {
                        entry.* = null;
                        self.active_count -= 1;
                        return true;
                    }
                }
            }
            return false;
        }

        pub fn retain(self: *Self, active_keys: []const KeyType) void {
            for (&self.entries) |*entry| {
                if (entry.*) |k| {
                    var found = false;
                    for (active_keys) |active| {
                        if (keysEqual(KeyType, k, active)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        entry.* = null;
                        self.active_count -= 1;
                    }
                }
            }
        }

        pub fn clear(self: *Self) void {
            @memset(&self.entries, null);
            self.active_count = 0;
        }

        pub fn count(self: *const Self) usize {
            return self.active_count;
        }
    };
}

/// Compact key registry with inline byte buffers for string keys like UUIDs and slugs.
pub fn StringCompactKeys(comptime max_key_len: usize, comptime capacity: usize) type {
    if (capacity == 0 or capacity > std.math.maxInt(u32)) {
        @compileError("StringCompactKeys capacity must be between 1 and 2^32-1");
    }
    const Entry = struct {
        bytes: [max_key_len]u8 = undefined,
        len: usize = 0,
        active: bool = false,

        fn slice(self: *const @This()) []const u8 {
            return self.bytes[0..self.len];
        }
    };

    return struct {
        const Self = @This();

        entries: [capacity]Entry = @splat(.{}),
        active_count: usize = 0,

        pub fn get(self: *const Self, key: []const u8) ?u32 {
            for (self.entries[0..], 0..) |*entry, i| {
                if (entry.active and std.mem.eql(u8, entry.slice(), key)) {
                    return @intCast(i);
                }
            }
            return null;
        }

        pub fn getOrAssign(self: *Self, key: []const u8) error{ CapacityExceeded, KeyTooLong }!u32 {
            if (key.len > max_key_len) return error.KeyTooLong;
            if (self.get(key)) |slot| return slot;
            for (&self.entries, 0..) |*entry, i| {
                if (!entry.active) {
                    @memcpy(entry.bytes[0..key.len], key);
                    entry.len = key.len;
                    entry.active = true;
                    self.active_count += 1;
                    return @intCast(i);
                }
            }
            return error.CapacityExceeded;
        }

        pub fn release(self: *Self, key: []const u8) bool {
            for (&self.entries) |*entry| {
                if (entry.active and std.mem.eql(u8, entry.slice(), key)) {
                    entry.active = false;
                    self.active_count -= 1;
                    return true;
                }
            }
            return false;
        }

        pub fn retain(self: *Self, active_keys: []const []const u8) void {
            for (&self.entries) |*entry| {
                if (entry.active) {
                    var found = false;
                    for (active_keys) |active| {
                        if (std.mem.eql(u8, entry.slice(), active)) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        entry.active = false;
                        self.active_count -= 1;
                    }
                }
            }
        }

        pub fn clear(self: *Self) void {
            for (&self.entries) |*entry| entry.active = false;
            self.active_count = 0;
        }

        pub fn count(self: *const Self) usize {
            return self.active_count;
        }
    };
}

test "CompactKeyRegistry retains stable slot across reordering and recycles vacant slots" {
    var reg = CompactKeyRegistry(u64, 4){};

    // Initial assignment
    const id_a = try reg.getOrAssign(1001);
    const id_b = try reg.getOrAssign(2002);
    const id_c = try reg.getOrAssign(3003);

    try std.testing.expectEqual(@as(u32, 0), id_a);
    try std.testing.expectEqual(@as(u32, 1), id_b);
    try std.testing.expectEqual(@as(u32, 2), id_c);
    try std.testing.expectEqual(@as(usize, 3), reg.count());

    // Reordering: lookup in reverse order returns identical slot indices
    try std.testing.expectEqual(@as(u32, 2), try reg.getOrAssign(3003));
    try std.testing.expectEqual(@as(u32, 0), try reg.getOrAssign(1001));
    try std.testing.expectEqual(@as(u32, 1), try reg.getOrAssign(2002));

    // Release id_b (slot 1)
    try std.testing.expect(reg.release(2002));
    try std.testing.expectEqual(@as(usize, 2), reg.count());
    try std.testing.expect(reg.get(2002) == null);

    // New item claims recycled slot 1
    const id_d = try reg.getOrAssign(4004);
    try std.testing.expectEqual(@as(u32, 1), id_d);

    // Retain only 1001 and 4004 (drops 3003 at slot 2)
    reg.retain(&.{ 1001, 4004 });
    try std.testing.expectEqual(@as(usize, 2), reg.count());
    try std.testing.expect(reg.get(3003) == null);

    // Slot 2 is now available
    const id_e = try reg.getOrAssign(5005);
    try std.testing.expectEqual(@as(u32, 2), id_e);

    // Capacity bound check
    _ = try reg.getOrAssign(6006); // claims slot 3 (capacity 4 reached)
    try std.testing.expectEqual(@as(usize, 4), reg.count());
    try std.testing.expectError(error.CapacityExceeded, reg.getOrAssign(7007));
}

test "StringCompactKeys stores inline string buffers and preserves UUID identity" {
    var reg = StringCompactKeys(36, 4){};

    const uuid1 = "018f3a5e-b24a-7182-9a3b-28f09e80a001";
    const uuid2 = "018f3a5e-b24a-7182-9a3b-28f09e80a002";
    const uuid3 = "018f3a5e-b24a-7182-9a3b-28f09e80a003";

    const s1 = try reg.getOrAssign(uuid1);
    const s2 = try reg.getOrAssign(uuid2);
    const s3 = try reg.getOrAssign(uuid3);

    try std.testing.expectEqual(@as(u32, 0), s1);
    try std.testing.expectEqual(@as(u32, 1), s2);
    try std.testing.expectEqual(@as(u32, 2), s3);

    // Ephemeral stack buffer with same content preserves slot
    var buf: [36]u8 = undefined;
    @memcpy(&buf, uuid2);
    try std.testing.expectEqual(@as(u32, 1), try reg.getOrAssign(&buf));

    // Exceeding max_key_len returns KeyTooLong
    try std.testing.expectError(error.KeyTooLong, reg.getOrAssign("this-string-is-longer-than-the-maximum-declared-thirty-six-bytes"));

    // Retain drops absent UUIDs
    reg.retain(&.{uuid1});
    try std.testing.expectEqual(@as(usize, 1), reg.count());
    try std.testing.expect(reg.get(uuid2) == null);
    try std.testing.expect(reg.get(uuid3) == null);

    // Slot 1 recycled
    const s4 = try reg.getOrAssign("018f3a5e-b24a-7182-9a3b-28f09e80a004");
    try std.testing.expectEqual(@as(u32, 1), s4);
}
