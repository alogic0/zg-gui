//! Deterministic SVG generator for diagrams.
//! Emits safe, inert SVG with semantic CSS classes and strict XML escaping.
const std = @import("std");

pub const EscapeWriter = struct {
    pub fn writeEscaped(writer: anytype, str: []const u8) !void {
        for (str) |c| {
            switch (c) {
                '&' => try writer.writeAll("&amp;"),
                '<' => try writer.writeAll("&lt;"),
                '>' => try writer.writeAll("&gt;"),
                '"' => try writer.writeAll("&quot;"),
                '\'' => try writer.writeAll("&#39;"),
                else => try writer.writeByte(c),
            }
        }
    }
};

pub const TextAnchor = enum {
    start,
    middle,
    end,

    pub fn asString(self: TextAnchor) []const u8 {
        return switch (self) {
            .start => "start",
            .middle => "middle",
            .end => "end",
        };
    }
};

pub const SvgWriter = struct {
    writer: std.Io.Writer.Allocating,

    pub fn init(allocator: std.mem.Allocator) SvgWriter {
        return .{
            .writer = std.Io.Writer.Allocating.init(allocator),
        };
    }

    pub fn deinit(self: *SvgWriter) void {
        self.writer.deinit();
    }

    /// Drawing sinks may use semantic entities to retain primitive identities.
    pub fn entity(_: *SvgWriter, _: anytype) !void {}

    pub fn startSvg(self: *SvgWriter, width: f32, height: f32) !void {
        try self.writer.writer.print(
            \\<svg xmlns="http://www.w3.org/2000/svg" class="zig-diagram-svg" viewBox="0 0 {d:.1} {d:.1}" width="{d:.1}" height="{d:.1}">
            \\
        , .{ width, height, width, height });
    }

    pub fn endSvg(self: *SvgWriter) !void {
        try self.writer.writer.writeAll("</svg>\n");
    }

    pub fn writeStandardDefs(self: *SvgWriter) !void {
        const defs =
            \\  <defs>
            \\    <marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            \\      <path d="M 0 1 L 10 5 L 0 9 z" class="zig-diagram-arrow" />
            \\    </marker>
            \\    <marker id="arrow-open" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="6" markerHeight="6" orient="auto-start-reverse">
            \\      <path d="M 1 1 L 9 5 L 1 9" class="zig-diagram-arrow-open" fill="none" />
            \\    </marker>
            \\    <marker id="cross" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            \\      <path d="M 1 1 L 9 9 M 9 1 L 1 9" class="zig-diagram-cross" />
            \\    </marker>
            \\    <marker id="circle" viewBox="0 0 10 10" refX="5" refY="5" markerWidth="6" markerHeight="6" orient="auto">
            \\      <circle cx="5" cy="5" r="3" class="zig-diagram-arrow" />
            \\    </marker>
            \\  </defs>
            \\
        ;
        try self.writer.writer.writeAll(defs);
    }

    pub fn startGroup(self: *SvgWriter, class: []const u8) !void {
        try self.writer.writer.print("  <g class=\"{s}\">\n", .{class});
    }

    pub fn endGroup(self: *SvgWriter) !void {
        try self.writer.writer.writeAll("  </g>\n");
    }

    pub fn rect(
        self: *SvgWriter,
        x: f32,
        y: f32,
        width: f32,
        height: f32,
        rx: f32,
        ry: f32,
        class: []const u8,
    ) !void {
        if (rx > 0 or ry > 0) {
            try self.writer.writer.print("    <rect x=\"{d:.1}\" y=\"{d:.1}\" width=\"{d:.1}\" height=\"{d:.1}\" rx=\"{d:.1}\" ry=\"{d:.1}\" class=\"{s}\" />\n", .{ x, y, width, height, rx, ry, class });
        } else {
            try self.writer.writer.print("    <rect x=\"{d:.1}\" y=\"{d:.1}\" width=\"{d:.1}\" height=\"{d:.1}\" class=\"{s}\" />\n", .{ x, y, width, height, class });
        }
    }

    pub fn circle(
        self: *SvgWriter,
        cx: f32,
        cy: f32,
        r: f32,
        class: []const u8,
    ) !void {
        try self.writer.writer.print("    <circle cx=\"{d:.1}\" cy=\"{d:.1}\" r=\"{d:.1}\" class=\"{s}\" />\n", .{ cx, cy, r, class });
    }

    pub fn polygon(
        self: *SvgWriter,
        points: []const [2]f32,
        class: []const u8,
    ) !void {
        try self.writer.writer.writeAll("    <polygon points=\"");
        for (points, 0..) |pt, i| {
            if (i > 0) try self.writer.writer.writeByte(' ');
            try self.writer.writer.print("{d:.1},{d:.1}", .{ pt[0], pt[1] });
        }
        try self.writer.writer.print("\" class=\"{s}\" />\n", .{class});
    }

    pub fn line(
        self: *SvgWriter,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        class: []const u8,
        marker_end: ?[]const u8,
    ) !void {
        if (marker_end) |m| {
            try self.writer.writer.print("    <line x1=\"{d:.1}\" y1=\"{d:.1}\" x2=\"{d:.1}\" y2=\"{d:.1}\" class=\"{s}\" marker-end=\"url(#{s})\" />\n", .{ x1, y1, x2, y2, class, m });
        } else {
            try self.writer.writer.print("    <line x1=\"{d:.1}\" y1=\"{d:.1}\" x2=\"{d:.1}\" y2=\"{d:.1}\" class=\"{s}\" />\n", .{ x1, y1, x2, y2, class });
        }
    }

    pub fn lineDotted(
        self: *SvgWriter,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        dash: []const u8,
        class: []const u8,
        marker_end: ?[]const u8,
    ) !void {
        if (marker_end) |m| {
            try self.writer.writer.print("    <line x1=\"{d:.1}\" y1=\"{d:.1}\" x2=\"{d:.1}\" y2=\"{d:.1}\" class=\"{s}\" stroke-dasharray=\"{s}\" marker-end=\"url(#{s})\" />\n", .{ x1, y1, x2, y2, class, dash, m });
        } else {
            try self.writer.writer.print("    <line x1=\"{d:.1}\" y1=\"{d:.1}\" x2=\"{d:.1}\" y2=\"{d:.1}\" class=\"{s}\" stroke-dasharray=\"{s}\" />\n", .{ x1, y1, x2, y2, class, dash });
        }
    }

    pub fn path(
        self: *SvgWriter,
        d: []const u8,
        class: []const u8,
        marker_end: ?[]const u8,
    ) !void {
        if (marker_end) |m| {
            try self.writer.writer.print("    <path d=\"{s}\" class=\"{s}\" marker-end=\"url(#{s})\" />\n", .{ d, class, m });
        } else {
            try self.writer.writer.print("    <path d=\"{s}\" class=\"{s}\" />\n", .{ d, class });
        }
    }

    pub fn textSingleLine(
        self: *SvgWriter,
        x: f32,
        y: f32,
        anchor: TextAnchor,
        class: []const u8,
        content: []const u8,
    ) !void {
        try self.writer.writer.print("    <text x=\"{d:.1}\" y=\"{d:.1}\" text-anchor=\"{s}\" class=\"{s}\">", .{ x, y, anchor.asString(), class });
        try EscapeWriter.writeEscaped(&self.writer.writer, content);
        try self.writer.writer.writeAll("</text>\n");
    }

    pub fn textMultiLine(
        self: *SvgWriter,
        x: f32,
        y: f32,
        line_height: f32,
        anchor: TextAnchor,
        class: []const u8,
        lines: []const []const u8,
    ) !void {
        if (lines.len == 0) return;
        try self.writer.writer.print("    <text x=\"{d:.1}\" y=\"{d:.1}\" text-anchor=\"{s}\" class=\"{s}\">\n", .{ x, y, anchor.asString(), class });

        for (lines, 0..) |l, i| {
            const dy = if (i == 0) @as(f32, 0.0) else line_height;
            try self.writer.writer.print("      <tspan x=\"{d:.1}\" dy=\"{d:.1}\">", .{ x, dy });
            try EscapeWriter.writeEscaped(&self.writer.writer, l);
            try self.writer.writer.writeAll("</tspan>\n");
        }
        try self.writer.writer.writeAll("    </text>\n");
    }

    pub fn toOwnedSlice(self: *SvgWriter) ![]u8 {
        return self.writer.toOwnedSlice();
    }
};

test "svg writer basic generation and escaping" {
    var svg = SvgWriter.init(std.testing.allocator);
    defer svg.deinit();

    try svg.startSvg(400.0, 300.0);
    try svg.writeStandardDefs();
    try svg.startGroup("zig-diagram-nodes");
    try svg.rect(10.0, 20.0, 100.0, 50.0, 4.0, 4.0, "zig-diagram-node-box");
    try svg.textSingleLine(60.0, 45.0, .middle, "zig-diagram-label", "Tom & <Jerry>");
    try svg.endGroup();
    try svg.endSvg();

    const out = try svg.toOwnedSlice();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "viewBox=\"0 0 400.0 300.0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "Tom &amp; &lt;Jerry&gt;") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "</svg>") != null);
}

test "svg multiline text with tspan" {
    var svg = SvgWriter.init(std.testing.allocator);
    defer svg.deinit();

    try svg.startSvg(200.0, 200.0);
    const lines = [_][]const u8{ "First line", "Second line" };
    try svg.textMultiLine(50.0, 50.0, 18.0, .middle, "zig-diagram-label", &lines);
    try svg.endSvg();

    const out = try svg.toOwnedSlice();
    defer std.testing.allocator.free(out);

    try std.testing.expect(std.mem.indexOf(u8, out, "<tspan x=\"50.0\" dy=\"0.0\">First line</tspan>") != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "<tspan x=\"50.0\" dy=\"18.0\">Second line</tspan>") != null);
}
