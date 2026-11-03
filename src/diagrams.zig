//! Optional typed drawing projections. Registered with a caller-selected engine.
const std = @import("std");
const gui = @import("zg_gui");
pub const engine = @import("diagram_engine");
pub const Scene = engine.Scene;

pub const ProjectOptions = struct {
    scene: *const Scene,
    namespace: gui.namespace.Range,
    description: []const u8,
};

/// Caller-owned identity state. Copy accepted state before composing a larger
/// candidate render; commit all copies/snapshots only after every writer passes.
pub fn Diagram(comptime capacity: struct { max_elements: usize, max_key_bytes: usize = 192 }) type {
    const max_elements = capacity.max_elements;
    const max_key_bytes = capacity.max_key_bytes;
    if (max_elements == 0 or max_elements > (std.math.maxInt(u32) - 3) / 4) @compileError("invalid diagram element capacity");
    return struct {
        const Self = @This();
        // Keep old slots reserved while assigning new entities. A removed entity
        // can never be mistaken for a new entity in the same patch transaction.
        const Keys = gui.StringCompactKeys(max_key_bytes, max_elements * 2);
        pub const node_count: u32 = 3 + max_elements * 4;
        pub const snapshot_capacity: usize = 8 + max_elements * 12;
        keys: Keys = .{},
        mounted: ?gui.namespace.Range = null,

        /// No heap allocation. Invalid admission and failed writes preserve this
        /// instance's identity state. Failed candidate output/snapshots are rolled
        /// back to their entry lengths; writer failure flags remain observable.
        pub fn project(self: *Self, p: anytype, input: ProjectOptions) !void {
            const ns = input.namespace;
            if (ns.first == 0 or ns.count < node_count or @as(u64, ns.first) + ns.count > @as(u64, std.math.maxInt(u32)) + 1) return error.InvalidNamespace;
            if (self.mounted) |old| if (old.first != ns.first or old.count != ns.count) return error.NamespaceChanged;
            if (!std.math.isFinite(input.scene.width) or !std.math.isFinite(input.scene.height) or input.scene.width <= 0 or input.scene.height <= 0) return error.InvalidGeometry;
            if (input.description.len == 0) return error.MissingDescription;
            const elements = input.scene.elements.items;
            if (elements.len > max_elements) return error.CapacityExceeded;
            var candidate = self.keys;
            var key_bytes: [max_elements][max_key_bytes]u8 = undefined;
            var key_slices: [max_elements][]const u8 = undefined;
            var nodes: [max_elements]u32 = undefined;
            for (elements, 0..) |element, i| {
                try validate(element);
                key_slices[i] = std.fmt.bufPrint(&key_bytes[i], "{s}:{d}:{d}:{s}", .{ @tagName(element.key.entity.kind), element.key.entity.index, element.key.part, element.key.entity.name }) catch return error.KeyTooLong;
                for (key_slices[0..i]) |other| if (std.mem.eql(u8, other, key_slices[i])) return error.DuplicateKey;
                const slot = try candidate.getOrAssign(key_slices[i]);
                nodes[i] = ns.first + 3 + slot * 2;
            }
            candidate.retain(key_slices[0..elements.len]);
            const html_len = p.html.len;
            const snapshot_len = p.next.len;
            const output_len = if (p.patches) |writer| writer.output.len else 0;
            errdefer {
                p.html.len = html_len;
                p.next.len = snapshot_len;
                if (p.patches) |writer| writer.output.len = output_len;
            }
            var dimensions: [128]u8 = undefined;
            const view_box = try std.fmt.bufPrint(&dimensions, "0 0 {d:.1} {d:.1}", .{ input.scene.width, input.scene.height });
            var prefix_buffer: [32]u8 = undefined;
            const prefix = try std.fmt.bufPrint(&prefix_buffer, "zg-diagram-{d}", .{ns.first});
            p.add("<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"zig-diagram-svg\" role=\"img\"");
            p.node(ns.first);
            p.attr(.{ .node = ns.first, .name = "viewBox", .value = view_box });
            p.attr(.{ .node = ns.first, .name = "aria-label", .value = input.description });
            p.add("><desc");
            p.node(ns.first + 1);
            p.add(">");
            p.text(.{ .node = ns.first + 1, .value = input.description });
            p.add("</desc>");
            definitions(p, prefix);
            const owner = ns.first + 2;
            p.add("<g");
            p.node(owner);
            p.add(">");
            p.keyedList(.{ .owner = owner, .nodes = nodes[0..elements.len] });
            for (elements, nodes[0..elements.len]) |element, node| {
                const child = p.beginChild(.{ .owner = owner, .node = node });
                p.add("<g");
                p.node(node);
                p.attr(.{ .node = node, .name = "class", .value = element.group });
                p.add(" data-diagram-name=\"");
                p.escaped(element.key.entity.name);
                p.print("\" data-diagram-part=\"{d}\" data-diagram-kind=\"{s}\">", .{ element.key.part, @tagName(element.key.entity.kind) });
                const shape = p.beginList(.{ .node = node, .membership = @tagName(element.shape) });
                try projectShape(p, .{ .element = element, .node = node + 1, .prefix = prefix });
                p.endList(shape);
                p.add("</g>");
                p.endChild(child);
            }
            p.order(.{ .owner = owner, .nodes = nodes[0..elements.len] });
            p.add("</g></svg>");
            if (p.html.failed or (if (p.patches) |writer| writer.output.failed else false)) return error.OutputOverflow;
            self.keys = candidate;
            self.mounted = ns;
        }
    };
}

fn validate(element: engine.drawing.Element) !void {
    switch (element.shape) {
        .rect => |r| {
            inline for (.{ "x", "y", "width", "height", "rx", "ry" }) |f| if (!std.math.isFinite(@field(r, f))) return error.InvalidGeometry;
            if (r.width < 0 or r.height < 0 or r.rx < 0 or r.ry < 0) return error.InvalidGeometry;
        },
        .circle => |c| {
            if (!std.math.isFinite(c.cx) or !std.math.isFinite(c.cy) or !std.math.isFinite(c.r) or c.r < 0) return error.InvalidGeometry;
        },
        .polygon => |points| {
            if (points.len == 0 or points.len > 64) return error.InvalidGeometry;
            for (points) |point| for (point) |value| if (!std.math.isFinite(value)) return error.InvalidGeometry;
        },
        .line => |l| {
            if (!std.math.isFinite(l.x1) or !std.math.isFinite(l.y1) or !std.math.isFinite(l.x2) or !std.math.isFinite(l.y2)) return error.InvalidGeometry;
            if (l.marker_end) |marker| if (!standardMarker(marker)) return error.InvalidMarker;
        },
        .path => |path| if (path.marker_end) |marker| {
            if (!standardMarker(marker)) return error.InvalidMarker;
        },
        .text => |t| if (!std.math.isFinite(t.x) or !std.math.isFinite(t.y)) return error.InvalidGeometry,
    }
}

fn standardMarker(value: []const u8) bool {
    inline for (.{ "arrow", "arrow-open", "cross", "circle" }) |name| if (std.mem.eql(u8, value, name)) return true;
    return false;
}

fn definitions(p: anytype, prefix: []const u8) void {
    p.add("<defs>");
    inline for (.{ "arrow", "arrow-open", "cross", "circle" }) |name| {
        p.print("<marker id=\"{s}-{s}\" viewBox=\"0 0 10 10\" refX=\"{d}\" refY=\"5\" markerWidth=\"6\" markerHeight=\"6\" orient=\"{s}\">", .{ prefix, name, if (comptime std.mem.eql(u8, name, "cross") or std.mem.eql(u8, name, "circle")) @as(u8, 5) else @as(u8, 9), if (comptime std.mem.eql(u8, name, "cross") or std.mem.eql(u8, name, "circle")) "auto" else "auto-start-reverse" });
        if (comptime std.mem.eql(u8, name, "circle")) {
            p.add("<circle cx=\"5\" cy=\"5\" r=\"3\" class=\"zig-diagram-arrow\"/>");
        } else if (comptime std.mem.eql(u8, name, "arrow-open")) {
            p.add("<path d=\"M 1 1 L 9 5 L 1 9\" class=\"zig-diagram-arrow-open\" fill=\"none\"/>");
        } else if (comptime std.mem.eql(u8, name, "cross")) {
            p.add("<path d=\"M 1 1 L 9 9 M 9 1 L 1 9\" class=\"zig-diagram-cross\"/>");
        } else p.add("<path d=\"M 0 1 L 10 5 L 0 9 z\" class=\"zig-diagram-arrow\"/>");
        p.add("</marker>");
    }
    p.add("</defs>");
}

fn number(p: anytype, node: u32, comptime name: []const u8, value: f32) !void {
    var bytes: [64]u8 = undefined;
    p.attr(.{ .node = node, .name = name, .value = try std.fmt.bufPrint(&bytes, "{d:.1}", .{value}) });
}

fn markerReference(p: anytype, input: struct { node: u32, prefix: []const u8, marker: ?[]const u8 }) !void {
    var bytes: [96]u8 = undefined;
    const value: ?[]const u8 = if (input.marker) |marker| try std.fmt.bufPrint(&bytes, "url(#{s}-{s})", .{ input.prefix, marker }) else null;
    gui.template.attribute(p, "marker-end", .{ .node = input.node, .value = value });
}

fn projectShape(p: anytype, input: struct { element: engine.drawing.Element, node: u32, prefix: []const u8 }) !void {
    const e = input.element;
    const node = input.node;
    p.print("<{s}", .{@tagName(e.shape)});
    p.node(node);
    p.attr(.{ .node = node, .name = "class", .value = e.class });
    switch (e.shape) {
        .rect => |r| inline for (.{ "x", "y", "width", "height", "rx", "ry" }) |f| try number(p, node, f, @field(r, f)),
        .circle => |c| inline for (.{ "cx", "cy", "r" }) |f| try number(p, node, f, @field(c, f)),
        .polygon => |points| {
            var bytes: [8192]u8 = undefined;
            var writer = gui.html.Writer{ .buffer = &bytes };
            for (points, 0..) |point, i| writer.print("{s}{d:.1},{d:.1}", .{ if (i == 0) "" else " ", point[0], point[1] });
            if (writer.failed) return error.OutputOverflow;
            p.attr(.{ .node = node, .name = "points", .value = writer.slice() });
        },
        .line => |l| {
            inline for (.{ "x1", "y1", "x2", "y2" }) |name| try number(p, node, name, @field(l, name));
            p.attr(.{ .node = node, .name = "stroke-dasharray", .value = l.dash });
            try markerReference(p, .{ .node = node, .prefix = input.prefix, .marker = l.marker_end });
        },
        .path => |path| {
            p.attr(.{ .node = node, .name = "d", .value = path.d });
            try markerReference(p, .{ .node = node, .prefix = input.prefix, .marker = path.marker_end });
        },
        .text => |t| {
            try number(p, node, "x", t.x);
            try number(p, node, "y", t.y);
            p.attr(.{ .node = node, .name = "text-anchor", .value = t.anchor.asString() });
            p.add(">");
            p.text(.{ .node = node, .value = t.content });
            p.add("</text>");
            return;
        },
    }
    p.add("/>");
}
