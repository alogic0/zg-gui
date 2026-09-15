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

/// Embedded document sources retain a distinct binding from image sources.
/// The caller supplies the sandbox and origin policy; the host enforces patches.
pub fn frameSource(p: anytype, input: anytype) void {
    if (@typeInfo(@TypeOf(input.value)) == .optional) {
        if (input.value) |value| frameSource(p, .{ .node = input.node, .value = value }) else p.attr(.{ .node = input.node, .name = "src", .value = null });
        return;
    }
    const value: []const u8 = input.value;
    if (!std.mem.eql(u8, value, "about:blank") and !validImageSource(value)) {
        p.html.failed = true;
        return;
    }
    p.attr(.{ .node = input.node, .name = "src", .value = value });
}

pub fn attribute(p: anytype, comptime name: []const u8, input: anytype) void {
    if (@typeInfo(@TypeOf(input.value)) == .optional) {
        if (input.value) |value| attribute(p, name, .{ .node = input.node, .value = value }) else p.attr(.{ .node = input.node, .name = name, .value = null });
        return;
    }
    if (comptime std.mem.eql(u8, name, "src")) {
        const value: []const u8 = input.value;
        if (!validImageSource(value)) {
            p.html.failed = true;
            return;
        }
    }
    if (comptime std.mem.eql(u8, name, "href")) {
        const value: []const u8 = input.value;
        if (std.mem.indexOfScalar(u8, value, '#') == null or std.mem.startsWith(u8, value, "//")) {
            p.html.failed = true;
            return;
        }
        for (value) |byte| if (!(std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "/._-#", byte) != null)) {
            p.html.failed = true;
            return;
        };
    }

    if (comptime std.mem.eql(u8, name, "disabled") or std.mem.eql(u8, name, "readonly") or
        std.mem.eql(u8, name, "inert") or std.mem.eql(u8, name, "autofocus") or std.mem.eql(u8, name, "required"))
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
    if (comptime std.mem.eql(u8, name, "value") or std.mem.eql(u8, name, "data-select-value")) {
        if (std.mem.indexOfAny(u8, value, "\t\r\n") != null) {
            p.html.failed = true;
            return;
        }
    }
    p.attr(.{ .node = input.node, .name = name, .value = value });
}

/// External destinations require explicit template opt-in and caller approval.
pub fn externalLinkHref(p: anytype, input: anytype) void {
    if (@typeInfo(@TypeOf(input.value)) == .optional) {
        if (input.value) |value| externalLinkHref(p, .{ .node = input.node, .value = value, .allow_http = @hasField(@TypeOf(input), "allow_http") and input.allow_http }) else p.attr(.{ .node = input.node, .name = "href", .value = null });
        return;
    }
    const value: []const u8 = input.value;
    const allows_http = @hasField(@TypeOf(input), "allow_http") and input.allow_http;
    if (!validExternalLink(.{ .value = value, .allow_http = allows_http })) {
        p.html.failed = true;
        return;
    }
    p.attr(.{ .node = input.node, .name = "href", .value = value });
}

/// Validate an optional resource before admitting it into a consumer view.
pub fn validExternalLink(input: struct { value: []const u8, allow_http: bool = false }) bool {
    return (std.mem.startsWith(u8, input.value, "https://") or (input.allow_http and std.mem.startsWith(u8, input.value, "http://"))) and validImageSource(input.value);
}

/// Checked same-origin route or fragment; encode characters outside this ASCII subset.
pub fn linkHref(p: anytype, input: anytype) void {
    const value: []const u8 = input.value;
    if (value.len == 0 or (value[0] != '/' and value[0] != '#') or std.mem.eql(u8, value, "#") or std.mem.startsWith(u8, value, "//")) {
        p.html.failed = true;
        return;
    }
    for (value) |byte| if (!(std.ascii.isAlphanumeric(byte) or std.mem.indexOfScalar(u8, "/._-~?&=%+#", byte) != null)) {
        p.html.failed = true;
        return;
    };
    p.attr(.{ .node = input.node, .name = "href", .value = value });
}

test "local links reject external and malformed references before writing" {
    const gui = @import("root.zig");
    const P = gui.Projection(1);
    var bytes: [256]u8 = undefined;
    for ([_][]const u8{ "", "https://example.test", "//example.test/x", "/\\example.test", "javascript:alert(1)", "/bad\npath", "/bad path", "/bad<path" }) |value| {
        var html = gui.html.Writer{ .buffer = &bytes };
        var snapshot = P.Snapshot{};
        var p = P{ .html = &html, .next = &snapshot };
        linkHref(&p, .{ .node = 1, .value = value });
        try std.testing.expect(html.failed and html.len == 0 and snapshot.len == 0);
    }
}

/// Bounded whole-number meter state; failure invalidates the candidate output.
pub fn meterValue(p: anytype, input: anytype) void {
    switch (@typeInfo(@TypeOf(input.value))) {
        .int, .comptime_int => {},
        else => @compileError("meter values must be integers"),
    }
    const value = std.math.cast(u32, input.value) orelse {
        p.html.failed = true;
        return;
    };
    const min = std.math.cast(u32, input.min) orelse {
        p.html.failed = true;
        return;
    };
    const max = std.math.cast(u32, input.max) orelse {
        p.html.failed = true;
        return;
    };
    if (min >= max or value < min or value > max) {
        p.html.failed = true;
        return;
    }
    attribute(p, "value", .{ .node = input.node, .value = value });
}

/// Finite determinate progress; callers own task state and admission.
pub fn progressValue(p: anytype, input: anytype) void {
    const value: f64 = switch (@typeInfo(@TypeOf(input.value))) {
        .float, .comptime_float => @floatCast(input.value),
        .int, .comptime_int => @floatFromInt(input.value),
        else => @compileError("progress values must be numbers"),
    };
    const max: f64 = @floatFromInt(input.max);
    if (!std.math.isFinite(value) or !std.math.isFinite(max) or max <= 0 or value < 0 or value > max) {
        p.html.failed = true;
        return;
    }
    var bytes: [512]u8 = undefined;
    const text_value = std.fmt.bufPrint(&bytes, "{d}", .{if (value == 0) @as(f64, 0) else value}) catch {
        p.html.failed = true;
        return;
    };
    p.attr(.{ .node = input.node, .name = "value", .value = text_value });
}

/// A coherent runtime range; validate both attributes before emitting either.
pub fn progressRange(p: anytype, input: anytype) void {
    const max = progressNumber(input.max);
    const value = progressNumber(input.value);
    if (!std.math.isFinite(max) or max <= 0 or !std.math.isFinite(value) or value < 0 or value > max) {
        p.html.failed = true;
        return;
    }
    var max_bytes: [512]u8 = undefined;
    var value_bytes: [512]u8 = undefined;
    const max_text = std.fmt.bufPrint(&max_bytes, "{d}", .{max}) catch {
        p.html.failed = true;
        return;
    };
    const value_text = std.fmt.bufPrint(&value_bytes, "{d}", .{if (value == 0) @as(f64, 0) else value}) catch {
        p.html.failed = true;
        return;
    };
    p.attr(.{ .node = input.node, .name = "max", .value = max_text });
    p.attr(.{ .node = input.node, .name = "value", .value = value_text });
}

fn progressNumber(value: anytype) f64 {
    return switch (@typeInfo(@TypeOf(value))) {
        .float, .comptime_float => @floatCast(value),
        .int, .comptime_int => @floatFromInt(value),
        else => @compileError("progress values must be numbers"),
    };
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

/// A reserved DOM ID range with optional explicitly owned external identities.
pub const Namespace = struct {
    first: u32 = 1,
    count: u32 = std.math.maxInt(u32),
    overrides: []const Override = &.{},
    pub const Override = struct { local: u32, node: u32 };
    fn contains(s: Namespace, id: u32) bool {
        return id >= s.first and @as(u64, id) < @as(u64, s.first) + s.count;
    }
    pub fn check(s: Namespace) error{NamespaceOverflow}!void {
        if (s.first == 0 or s.count == 0 or @as(u64, s.first) + s.count - 1 > std.math.maxInt(u32)) return error.NamespaceOverflow;
        for (s.overrides, 0..) |entry, i| {
            if (entry.local == 0 or entry.local > s.count or entry.node == 0) return error.NamespaceOverflow;
            if (s.contains(entry.node) and entry.node != @as(u64, s.first) + entry.local - 1) return error.NamespaceOverflow;
            for (s.overrides[0..i]) |previous| {
                if (previous.local == entry.local or previous.node == entry.node) return error.NamespaceOverflow;
            }
        }
    }
    pub fn validate(comptime s: Namespace) void {
        s.check() catch @compileError("invalid template namespace range or identity override");
    }
    pub fn node(s: Namespace, local: u32) error{NamespaceOverflow}!u32 {
        try s.check();
        if (local == 0 or local > s.count) return error.NamespaceOverflow;
        for (s.overrides) |entry| if (entry.local == local) return entry.node;
        return @intCast(@as(u64, s.first) + local - 1);
    }
};
/// Validate all reserved ranges and external identities in a composition.
pub fn validateNamespaces(comptime spaces: []const Namespace) void {
    for (spaces, 0..) |s, i| {
        s.validate();
        for (spaces[0..i]) |other| {
            if (@as(u64, s.first) < @as(u64, other.first) + other.count and
                @as(u64, other.first) < @as(u64, s.first) + s.count)
                @compileError("overlapping template namespaces");
            for (s.overrides) |entry| {
                if (other.contains(entry.node)) @compileError("overlapping template identity");
                for (other.overrides) |previous| {
                    if (entry.node == previous.node) @compileError("overlapping template identity");
                }
            }
            for (other.overrides) |entry| {
                if (s.contains(entry.node)) @compileError("overlapping template identity");
            }
        }
    }
}

test "explicit identities reject ambiguous ownership" {
    try std.testing.expectEqual(std.math.maxInt(u32), try (Namespace{ .first = std.math.maxInt(u32), .count = 1, .overrides = &.{.{ .local = 1, .node = std.math.maxInt(u32) }} }).node(1));
    const space = Namespace{ .first = 100, .count = 20, .overrides = &.{.{ .local = 2, .node = 7 }} };
    try std.testing.expectEqual(@as(u32, 7), try space.node(2));
    try std.testing.expectEqual(@as(u32, 102), try space.node(3));
    for ([_]Namespace{
        .{ .first = 100, .count = 20, .overrides = &.{.{ .local = 0, .node = 7 }} },
        .{ .first = 100, .count = 20, .overrides = &.{.{ .local = 21, .node = 7 }} },
        .{ .first = 100, .count = 20, .overrides = &.{.{ .local = 2, .node = 0 }} },
        .{ .first = 100, .count = 20, .overrides = &.{.{ .local = 2, .node = 102 }} },
        .{ .first = 100, .count = 20, .overrides = &.{ .{ .local = 2, .node = 7 }, .{ .local = 3, .node = 7 } } },
        .{ .first = 100, .count = 20, .overrides = &.{ .{ .local = 2, .node = 7 }, .{ .local = 2, .node = 8 } } },
    }) |invalid| try std.testing.expectError(error.NamespaceOverflow, invalid.node(1));
    comptime validateNamespaces(&.{ space, .{ .first = 200, .count = 20, .overrides = &.{.{ .local = 2, .node = 8 }} } });
}

test "template namespace bounds reject overflow and preserve disjoint ranges" {
    comptime validateNamespaces(&.{ .{ .first = 10, .count = 10 }, .{ .first = 20, .count = 10 } });
    const space = Namespace{ .first = 10, .count = 10 };
    try std.testing.expectEqual(@as(u32, 10), try space.node(1));
    try std.testing.expectEqual(@as(u32, 19), try space.node(10));
    try std.testing.expectError(error.NamespaceOverflow, space.node(11));
    try std.testing.expectError(error.NamespaceOverflow, space.node(0));
    try std.testing.expectError(error.NamespaceOverflow, (Namespace{ .first = std.math.maxInt(u32) }).node(2));
}

test "dynamic SVG references reject protocols before publishing initial markup" {
    const gui = @import("root.zig");
    const P = gui.Projection(1);
    var bytes: [256]u8 = undefined;
    for ([_][]const u8{ "javascript:alert(1)#x", "//outside.test/icons.svg#x", "data:text/html,x#y" }) |value| {
        var html = gui.html.Writer{ .buffer = &bytes };
        var snapshot = P.Snapshot{};
        var p = P{ .html = &html, .next = &snapshot };
        attribute(&p, "href", .{ .node = 1, .value = value });
        try std.testing.expect(html.failed);
        try std.testing.expectEqual(@as(usize, 0), html.len);
    }
}

test "select values reject lossy attribute control characters and optional icons can clear" {
    const gui = @import("root.zig");
    const P = gui.Projection(1);
    var bytes: [256]u8 = undefined;
    inline for (.{ "value", "data-select-value" }) |name| {
        var html = gui.html.Writer{ .buffer = &bytes };
        var snapshot = P.Snapshot{};
        var p = P{ .html = &html, .next = &snapshot };
        attribute(&p, name, .{ .node = 1, .value = "line\nbreak" });
        try std.testing.expect(html.failed and html.len == 0);
    }
    var html = gui.html.Writer{ .buffer = &bytes };
    var snapshot = P.Snapshot{};
    var p = P{ .html = &html, .next = &snapshot };
    attribute(&p, "href", .{ .node = 1, .value = @as(?[]const u8, null) });
    try std.testing.expect(!html.failed);
}

/// Validate even static component views, whose fields are not otherwise read.
pub fn componentInput(value: anytype, comptime location: []const u8) void {
    const T = @TypeOf(value);
    const Base = switch (@typeInfo(T)) {
        .pointer => |p| if (p.size == .one) p.child else @compileError(location ++ ": component input requires a struct or a single-item struct pointer"),
        else => T,
    };
    if (@typeInfo(Base) != .@"struct") @compileError(location ++ ": component input requires a struct");
}

/// A typed child projection. Capacity, membership and descendant IDs belong to
/// the composing consumer; the generated template owns only the slot element.
pub fn projectSlot(p: anytype, input: anytype) void {
    componentInput(input.value, "template slot");
    input.value.project(p, .{ .node = input.node });
}

test "slot children share failure admission and do not hide snapshot costs" {
    const gui = @import("root.zig");
    const Children = struct {
        pub fn project(_: @This(), p: anytype, owner: struct { node: u32 }) void {
            p.text(.{ .node = owner.node + 1, .value = "first" });
            p.text(.{ .node = owner.node + 2, .value = "second" });
        }
    };
    const P = gui.Projection(1);
    var bytes: [64]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var next = P.Snapshot{};
    var p = P{ .html = &html, .next = &next };
    projectSlot(&p, .{ .value = Children{}, .node = 100 });
    try std.testing.expect(html.failed);
}

/// An admitted integer with a closed CSS unit, never an arbitrary CSS string.
pub const StyleValue = struct {
    value: i64,
    unit: enum { number, px, percent } = .number,
};

/// Fixed numeric custom properties, serialized completely before publication.
pub fn styleVariables(p: anytype, input: anytype) void {
    const T = @TypeOf(input.value);
    if (@typeInfo(T) == .optional) {
        if (input.value) |value| styleVariables(p, .{ .node = input.node, .value = value }) else p.attr(.{ .node = input.node, .name = "data-style-vars", .value = null });
        return;
    }
    if (@typeInfo(T) != .@"struct") @compileError("style variables require a struct of named integers");
    const fields = @typeInfo(T).@"struct".field_names;
    if (fields.len == 0 or fields.len > 16) @compileError("style variables require 1 to 16 fields");
    var bytes: [16 * 88]u8 = undefined;
    var len: usize = 0;
    inline for (fields, 0..) |name, i| {
        comptime {
            if (name.len < 3 or name.len > 64 or !std.mem.startsWith(u8, name, "--") or name[2] < 'a' or name[2] > 'z')
                @compileError("style variable names must match --[a-z][a-z0-9-]* and fit 64 bytes");
            for (name[3..]) |byte| if (!(byte >= 'a' and byte <= 'z') and !(byte >= '0' and byte <= '9') and byte != '-')
                @compileError("invalid style variable name");
            if (@FieldType(T, name) != StyleValue and @typeInfo(@FieldType(T, name)) != .int and @typeInfo(@FieldType(T, name)) != .comptime_int)
                @compileError("style variable values must be integers");
        }
        const field = @field(input.value, name);
        const value = if (@TypeOf(field) == StyleValue) field.value else std.math.cast(i64, field) orelse {
            p.html.failed = true;
            return;
        };
        const unit = if (@TypeOf(field) == StyleValue) switch (field.unit) {
            .number => "",
            .px => "px",
            .percent => "%",
        } else "";
        const part = std.fmt.bufPrint(bytes[len..], "{s}{s}:{d}{s}", .{ if (i == 0) "" else ";", name, value, unit }) catch {
            p.html.failed = true;
            return;
        };
        len += part.len;
    }
    p.attr(.{ .node = input.node, .name = "data-style-vars", .value = bytes[0..len] });
}

fn validImageSource(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| if (byte <= 0x20 or byte == 0x7f or byte == '\\') return false;
    if (std.mem.startsWith(u8, value, "/")) return !std.mem.startsWith(u8, value, "//");
    const uri = std.Uri.parse(value) catch return false;
    return (std.mem.eql(u8, uri.scheme, "https") or std.mem.eql(u8, uri.scheme, "http")) and uri.host != null and switch (uri.host.?) {
        .raw => |v| v.len > 0,
        .percent_encoded => |v| v.len > 0,
    } and uri.user == null and uri.password == null;
}

test "optional style groups clear only their attribute and retry failed output" {
    const gui = @import("root.zig");
    const P = gui.Projection(1);
    const Style = struct { @"--offset": StyleValue };
    var bytes: [256]u8 = undefined;
    var output = gui.html.Writer{ .buffer = &bytes };
    var scratch_bytes: [256]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &scratch_bytes };
    var before = P.Snapshot{};
    var initial = P{ .html = &html, .next = &before };
    styleVariables(&initial, .{ .node = @as(u32, 20), .value = @as(?Style, .{ .@"--offset" = .{ .value = -12, .unit = .px } }) });
    try std.testing.expect(!html.failed);
    var after = P.Snapshot{};
    var writer = gui.patch.Writer{ .output = &output };
    var p = P{ .html = &html, .patches = &writer, .previous = &before, .next = &after, .writing = false };
    styleVariables(&p, .{ .node = @as(u32, 20), .value = @as(?Style, null) });
    try std.testing.expectEqualStrings("R\t20\tdata-style-vars\n", output.slice());
    var tiny: [1]u8 = undefined;
    var failed = gui.html.Writer{ .buffer = &tiny };
    var failed_writer = gui.patch.Writer{ .output = &failed };
    var retry = P.Snapshot{};
    var retry_p = P{ .html = &html, .patches = &failed_writer, .previous = &after, .next = &retry, .writing = false };
    styleVariables(&retry_p, .{ .node = @as(u32, 20), .value = @as(?Style, .{ .@"--offset" = .{ .value = 8, .unit = .percent } }) });
    try std.testing.expect(failed.failed);
    output.len = 0;
    retry = .{};
    retry_p.patches = &writer;
    styleVariables(&retry_p, .{ .node = @as(u32, 20), .value = @as(?Style, .{ .@"--offset" = .{ .value = 8, .unit = .percent } }) });
    try std.testing.expectEqualStrings("A\t20\tdata-style-vars\t--offset:8%\n", output.slice());
}
