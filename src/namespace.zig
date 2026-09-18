//! Deterministic named allocation, with fixed reservations for existing IDs.
const std = @import("std");
pub const Declaration = struct { name: []const u8, count: u32, first: ?u32 = null };
pub const Range = struct {
    first: u32,
    count: u32,
    pub fn id(self: Range, index: usize) error{OutsideNamespace}!u32 {
        if (index >= self.count) return error.OutsideNamespace;
        return self.first + @as(u32, @intCast(index));
    }
    pub fn child(self: Range, input: struct { offset: u32, count: u32 }) error{OutsideNamespace}!Range {
        if (input.count == 0 or input.offset >= self.count or input.count > self.count - input.offset)
            return error.OutsideNamespace;
        return .{ .first = self.first + input.offset, .count = input.count };
    }
};
pub const AllocationError = error{ InvalidName, DuplicateName, InvalidRange, Overlap, Exhausted, WrongOutputLength };

pub fn allocate(input: struct { declarations: []const Declaration, output: []Range }) AllocationError!void {
    const declarations = input.declarations;
    const output = input.output;
    if (output.len != declarations.len) return error.WrongOutputLength;
    // Validate every fixed reservation before automatic placement.
    for (declarations, 0..) |declaration, i| {
        if (declaration.name.len == 0) return error.InvalidName;
        if (declaration.count == 0) return error.InvalidRange;
        for (declarations[0..i]) |earlier| {
            if (std.mem.eql(u8, declaration.name, earlier.name)) return error.DuplicateName;
        }
        output[i] = .{ .first = declaration.first orelse 0, .count = declaration.count };
        if (declaration.first) |first| {
            if (first == 0 or @as(u64, first) + declaration.count > @as(u64, std.math.maxInt(u32)) + 1)
                return error.InvalidRange;
            for (output[0..i]) |earlier| {
                if (earlier.first != 0 and overlaps(output[i], earlier)) return error.Overlap;
            }
        }
    }
    for (output) |*range| {
        if (range.first != 0) continue;
        var candidate: u64 = 1;
        search: while (true) {
            if (candidate + range.count > @as(u64, std.math.maxInt(u32)) + 1) return error.Exhausted;
            const proposed = Range{ .first = @intCast(candidate), .count = range.count };
            for (output) |other| {
                if (other.first != 0 and overlaps(proposed, other)) {
                    candidate = @as(u64, other.first) + other.count;
                    continue :search;
                }
            }
            range.first = @intCast(candidate);
            break;
        }
    }
}
fn overlaps(a: Range, b: Range) bool {
    return @as(u64, a.first) < @as(u64, b.first) + b.count and @as(u64, b.first) < @as(u64, a.first) + a.count;
}

pub fn Registry(comptime declarations: []const Declaration) type {
    return struct {
        const ranges = blk: {
            @setEvalBranchQuota(10000 + declarations.len * declarations.len * 100);
            var result: [declarations.len]Range = undefined;
            allocate(.{ .declarations = declarations, .output = &result }) catch |err|
                @compileError("node namespace allocation: " ++ @errorName(err));
            break :blk result;
        };
        pub fn range(comptime name: []const u8) Range {
            inline for (declarations, 0..) |declaration, i| {
                if (comptime std.mem.eql(u8, name, declaration.name)) return ranges[i];
            }
            @compileError("unknown node namespace: " ++ name);
        }
    };
}

test "named namespaces reserve fixed IDs before deterministic automatic placement" {
    const Names = Registry(&.{
        .{ .name = "automatic", .count = 4 },
        .{ .name = "legacy", .count = 10, .first = 1 },
        .{ .name = "island", .count = 2, .first = 14 },
        .{ .name = "small", .count = 3 },
    });
    try std.testing.expectEqual(@as(u32, 16), Names.range("automatic").first);
    try std.testing.expectEqual(@as(u32, 11), Names.range("small").first);
    try std.testing.expectEqual(@as(u32, 19), try Names.range("automatic").id(3));
    try std.testing.expectError(error.OutsideNamespace, Names.range("automatic").id(4));
    try std.testing.expectEqual(Range{ .first = 17, .count = 2 }, try Names.range("automatic").child(.{ .offset = 1, .count = 2 }));
    try std.testing.expectError(error.OutsideNamespace, Names.range("automatic").child(.{ .offset = 3, .count = 2 }));
    try std.testing.expectError(error.OutsideNamespace, Names.range("automatic").child(.{ .offset = 0, .count = 0 }));
}

test "namespace allocation rejects invalid declarations and exhaustion" {
    var output: [2]Range = undefined;
    try std.testing.expectError(error.DuplicateName, allocate(.{ .declarations = &.{ .{ .name = "x", .count = 1 }, .{ .name = "x", .count = 1 } }, .output = &output }));
    try std.testing.expectError(error.Overlap, allocate(.{ .declarations = &.{ .{ .name = "x", .count = 5, .first = 10 }, .{ .name = "y", .count = 1, .first = 14 } }, .output = &output }));
    try std.testing.expectError(error.Exhausted, allocate(.{ .declarations = &.{ .{ .name = "x", .count = std.math.maxInt(u32), .first = 1 }, .{ .name = "y", .count = 1 } }, .output = &output }));
    for ([_]Declaration{ .{ .name = "x", .count = 0 }, .{ .name = "x", .count = 1, .first = 0 }, .{ .name = "x", .count = 2, .first = std.math.maxInt(u32) } }) |declaration|
        try std.testing.expectError(error.InvalidRange, allocate(.{ .declarations = &.{declaration}, .output = output[0..1] }));
    try std.testing.expectError(error.InvalidName, allocate(.{ .declarations = &.{.{ .name = "", .count = 1 }}, .output = output[0..1] }));
    const last = Registry(&.{.{ .name = "last", .count = 1, .first = std.math.maxInt(u32) }}).range("last");
    try std.testing.expectEqual(std.math.maxInt(u32), try last.id(0));
}
