//! Owned, bounded drawing commands shared by SVG export and interactive hosts.
const std = @import("std");
const svg = @import("svg.zig");

pub const Limits = struct {
    max_elements: usize = 2048,
    max_data_bytes: usize = 256 * 1024,
};

pub const EntityKind = enum { anonymous, flow_node, flow_edge, flow_subgraph, participant, lifeline, event, title, activation };
pub const Entity = struct { kind: EntityKind, name: []const u8 = "", index: u32 = 0 };
pub const Key = struct {
    entity: Entity,
    part: u32,

    pub fn eql(a: Key, b: Key) bool {
        return a.entity.kind == b.entity.kind and a.entity.index == b.entity.index and
            a.part == b.part and std.mem.eql(u8, a.entity.name, b.entity.name);
    }
};

pub const Rect = struct { x: f32, y: f32, width: f32, height: f32, rx: f32, ry: f32 };
pub const Circle = struct { cx: f32, cy: f32, r: f32 };
pub const Line = struct { x1: f32, y1: f32, x2: f32, y2: f32, dash: ?[]const u8 = null, marker_end: ?[]const u8 = null };
pub const Path = struct { d: []const u8, marker_end: ?[]const u8 = null };
pub const Text = struct { x: f32, y: f32, anchor: svg.TextAnchor, content: []const u8 };
pub const Shape = union(enum) { rect: Rect, circle: Circle, polygon: []const [2]f32, line: Line, path: Path, text: Text };
pub const Element = struct { key: Key, class: []const u8, group: []const u8, shape: Shape };
pub const Command = union(enum) { start_group: []const u8, end_group: void, element: usize };

pub const Scene = struct {
    arena: std.heap.ArenaAllocator,
    width: f32 = 0,
    height: f32 = 0,
    elements: std.ArrayList(Element) = .empty,
    commands: std.ArrayList(Command) = .empty,

    /// Releases every string, point array and command owned by the scene.
    pub fn deinit(self: *Scene) void {
        self.arena.deinit();
        self.* = undefined;
    }

    /// Returns allocator-owned SVG. Commands replay the layout's original draw
    /// order and group boundaries; geometry is never recalculated here.
    pub fn renderSvg(self: *const Scene, allocator: std.mem.Allocator) ![]u8 {
        var writer = svg.SvgWriter.init(allocator);
        errdefer writer.deinit();
        try writer.startSvg(self.width, self.height);
        try writer.writeStandardDefs();
        for (self.commands.items) |command| switch (command) {
            .start_group => |class| try writer.startGroup(class),
            .end_group => try writer.endGroup(),
            .element => |index| {
                const e = self.elements.items[index];
                switch (e.shape) {
                    .rect => |r| try writer.rect(r.x, r.y, r.width, r.height, r.rx, r.ry, e.class),
                    .circle => |c| try writer.circle(c.cx, c.cy, c.r, e.class),
                    .polygon => |points| try writer.polygon(points, e.class),
                    .line => |l| if (l.dash) |dash|
                        try writer.lineDotted(l.x1, l.y1, l.x2, l.y2, dash, e.class, l.marker_end)
                    else
                        try writer.line(l.x1, l.y1, l.x2, l.y2, e.class, l.marker_end),
                    .path => |p| try writer.path(p.d, e.class, p.marker_end),
                    .text => |t| try writer.textSingleLine(t.x, t.y, t.anchor, e.class, t.content),
                }
            },
        };
        try writer.endSvg();
        return writer.toOwnedSlice();
    }
};

/// A sink for Layout.draw. Every borrowed argument is copied before returning.
/// The caller discards/deinitializes the entire candidate after any error.
pub const Builder = struct {
    scene: Scene,
    limits: Limits,
    data_bytes: usize = 0,
    current: Entity = .{ .kind = .anonymous },
    part: u32 = 0,
    group: []const u8 = "",

    pub fn init(input: struct { allocator: std.mem.Allocator, limits: Limits = .{} }) Builder {
        return .{ .scene = .{ .arena = std.heap.ArenaAllocator.init(input.allocator) }, .limits = input.limits };
    }

    fn admit(self: *Builder, bytes: usize) !void {
        if (bytes > self.limits.max_data_bytes - self.data_bytes) return error.LimitExceeded;
        self.data_bytes += bytes;
    }

    fn copy(self: *Builder, value: []const u8) ![]const u8 {
        try self.admit(value.len);
        return self.scene.arena.allocator().dupe(u8, value);
    }

    fn optionalCopy(self: *Builder, value: ?[]const u8) !?[]const u8 {
        return if (value) |v| try self.copy(v) else null;
    }

    fn append(self: *Builder, class: []const u8, shape: Shape) !void {
        if (self.scene.elements.items.len >= self.limits.max_elements or self.part == std.math.maxInt(u32)) return error.LimitExceeded;
        const allocator = self.scene.arena.allocator();
        const index = self.scene.elements.items.len;
        try self.scene.elements.append(allocator, .{ .key = .{ .entity = self.current, .part = self.part }, .class = try self.copy(class), .group = self.group, .shape = shape });
        try self.scene.commands.append(allocator, .{ .element = index });
        self.part += 1;
    }

    pub fn entity(self: *Builder, input: Entity) !void {
        self.current = input;
        self.current.name = try self.copy(input.name);
        self.part = 0;
    }

    pub fn startSvg(self: *Builder, width: f32, height: f32) !void {
        if (!std.math.isFinite(width) or !std.math.isFinite(height) or width <= 0 or height <= 0) return error.InvalidGeometry;
        self.scene.width = width;
        self.scene.height = height;
    }

    pub fn endSvg(_: *Builder) !void {}
    pub fn writeStandardDefs(_: *Builder) !void {}

    pub fn startGroup(self: *Builder, class: []const u8) !void {
        if (self.group.len != 0) return error.NestedGroup;
        self.group = try self.copy(class);
        if (self.scene.commands.items.len > self.limits.max_elements *| 3) return error.LimitExceeded;
        try self.scene.commands.append(self.scene.arena.allocator(), .{ .start_group = self.group });
    }

    pub fn endGroup(self: *Builder) !void {
        self.group = "";
        try self.scene.commands.append(self.scene.arena.allocator(), .end_group);
    }

    pub fn rect(self: *Builder, x: f32, y: f32, width: f32, height: f32, rx: f32, ry: f32, class: []const u8) !void {
        try self.append(class, .{ .rect = .{ .x = x, .y = y, .width = width, .height = height, .rx = rx, .ry = ry } });
    }

    pub fn circle(self: *Builder, cx: f32, cy: f32, r: f32, class: []const u8) !void {
        try self.append(class, .{ .circle = .{ .cx = cx, .cy = cy, .r = r } });
    }

    pub fn polygon(self: *Builder, points: []const [2]f32, class: []const u8) !void {
        try self.admit(try std.math.mul(usize, points.len, @sizeOf([2]f32)));
        try self.append(class, .{ .polygon = try self.scene.arena.allocator().dupe([2]f32, points) });
    }

    pub fn line(self: *Builder, x1: f32, y1: f32, x2: f32, y2: f32, class: []const u8, marker_end: ?[]const u8) !void {
        try self.append(class, .{ .line = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .marker_end = try self.optionalCopy(marker_end) } });
    }

    pub fn lineDotted(self: *Builder, x1: f32, y1: f32, x2: f32, y2: f32, dash: []const u8, class: []const u8, marker_end: ?[]const u8) !void {
        try self.append(class, .{ .line = .{ .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .dash = try self.copy(dash), .marker_end = try self.optionalCopy(marker_end) } });
    }

    pub fn path(self: *Builder, d: []const u8, class: []const u8, marker_end: ?[]const u8) !void {
        try self.append(class, .{ .path = .{ .d = try self.copy(d), .marker_end = try self.optionalCopy(marker_end) } });
    }

    pub fn textSingleLine(self: *Builder, x: f32, y: f32, anchor: svg.TextAnchor, class: []const u8, content: []const u8) !void {
        try self.append(class, .{ .text = .{ .x = x, .y = y, .anchor = anchor, .content = try self.copy(content) } });
    }
};
