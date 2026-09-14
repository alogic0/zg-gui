//! Small typed adapters used by generated projections; no runtime parser.
const std = @import("std");

pub fn get(value: anytype, comptime path: []const u8, comptime location: []const u8) GetType(@TypeOf(value), path, location) {
    const dot = comptime std.mem.indexOfScalar(u8, path, '.');
    if (comptime dot) |index| return get(@field(value, path[0..index]), path[index + 1 ..], location);
    return @field(value, path);
}
fn GetType(comptime T: type, comptime path: []const u8, comptime location: []const u8) type {
    const Base = switch (@typeInfo(T)) {
        .pointer => |p| p.child,
        else => T,
    };
    const dot = std.mem.indexOfScalar(u8, path, '.');
    const name = path[0 .. dot orelse path.len];
    switch (@typeInfo(Base)) {
        .@"struct", .@"union" => {},
        else => @compileError(location ++ ": binding path does not refer to a struct"),
    }
    if (!@hasField(Base, name)) @compileError(location ++ ": unknown binding field '" ++ name ++ "'");
    const Field = @FieldType(Base, name);
    return if (dot) |index| GetType(Field, path[index + 1 ..], location) else Field;
}

fn string(buffer: []u8, value: anytype) ?[]const u8 {
    return switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => std.fmt.bufPrint(buffer, "{d}", .{value}) catch null,
        .bool => if (value) "true" else "false",
        .@"enum" => @tagName(value),
        .pointer => |p| switch (p.size) {
            .slice => if (p.child == u8) value else @compileError("template text requires a byte string"),
            .one => switch (@typeInfo(p.child)) {
                .array => |a| if (a.child == u8) value else @compileError("template text requires a byte string"),
                else => @compileError("template text requires a byte string"),
            },
            else => @compileError("template text requires a byte string"),
        },
        else => @compileError("template values must be strings, integers, Booleans or enums; format other values in the Zig view"),
    };
}

pub fn text(p: anytype, input: anytype) void {
    var bytes: [128]u8 = undefined;
    const value = string(&bytes, input.value) orelse {
        p.html.failed = true;
        return;
    };
    p.text(.{ .node = input.node, .value = value });
}

pub fn attribute(p: anytype, comptime name: []const u8, input: anytype) void {
    if (@typeInfo(@TypeOf(input.value)) == .optional) {
        if (input.value) |value| attribute(p, name, .{ .node = input.node, .value = value }) else p.attr(.{ .node = input.node, .name = name, .value = null });
        return;
    }
    if (comptime std.mem.eql(u8, name, "disabled") or std.mem.eql(u8, name, "readonly") or
        std.mem.eql(u8, name, "inert") or std.mem.eql(u8, name, "autofocus"))
    {
        if (@TypeOf(input.value) != bool) @compileError("Boolean HTML attributes require bool bindings");
        p.attr(.{ .node = input.node, .name = name, .value = if (input.value) "" else null });
        return;
    }
    var bytes: [128]u8 = undefined;
    const value = string(&bytes, input.value) orelse {
        p.html.failed = true;
        return;
    };
    p.attr(.{ .node = input.node, .name = name, .value = value });
}

pub fn event(p: anytype, comptime name: []const u8, input: anytype) void {
    if (@typeInfo(@TypeOf(input.value)) != .@"enum") @compileError("template actions and input kinds must be enum values");
    const value = std.math.cast(u32, @backingInt(input.value)) orelse {
        p.html.failed = true;
        return;
    };
    if (value == 0) {
        p.html.failed = true;
        return;
    }
    attribute(p, name, .{ .node = input.node, .value = value });
}

pub fn keyedId(input: struct { key: u32, slot: u32, stride: u32 }) error{InvalidKey}!u32 {
    if (input.slot == 0 or input.slot > input.stride) return error.InvalidKey;
    const id = (@as(u64, input.key) + 1) * input.stride + input.slot;
    return std.math.cast(u32, id) orelse error.InvalidKey;
}

test "keyed IDs separate template slots from repeated keys without overflow" {
    try std.testing.expectEqual(@as(u32, 12), try keyedId(.{ .key = 0, .slot = 2, .stride = 10 }));
    try std.testing.expectEqual(@as(u32, 22), try keyedId(.{ .key = 1, .slot = 2, .stride = 10 }));
    try std.testing.expectError(error.InvalidKey, keyedId(.{ .key = std.math.maxInt(u32), .slot = 2, .stride = 10 }));
}

test "typed lookup follows view fields and preserves borrowed strings" {
    const view = .{ .user = .{ .name = @as([]const u8, "name") } };
    try std.testing.expectEqualStrings("name", get(view, "user.name", "test"));
}
