//! Sugiyama layout solver and SVG renderer for flowcharts and graph diagrams.
//! Solves 2D layered coordinates and emits clean, responsive SVG.
const std = @import("std");
const parser = @import("flowchart_parser.zig");
const graph_mod = @import("graph.zig");
const layering_mod = @import("sugiyama_layering.zig");
const crossing_mod = @import("sugiyama_crossing.zig");
const font_mod = @import("font_metrics.zig");
const svg_mod = @import("svg.zig");

pub const LayoutOptions = struct {
    font_size: f32 = 14.0,
    node_padding_x: f32 = 24.0,
    node_height: f32 = 38.0,
    node_spacing: f32 = 40.0,
    layer_spacing: f32 = 56.0,
    margin_x: f32 = 36.0,
    margin_y: f32 = 36.0,
    crossing_iterations: usize = 6,
    max_label_width: f32 = 200.0,
    node_padding_y: f32 = 10.0,
    parallel_spacing: f32 = 40.0,
    self_loop_spacing: f32 = 48.0,
};

pub const FlowchartLayout = struct {
    diagram: *const parser.FlowchartDiagram,
    options: LayoutOptions,
    font: font_mod.Font,
    graph: graph_mod.DirectedGraph,
    link_indices: []usize,
    layered: layering_mod.LayeredGraph,
    total_width: f32,
    total_height: f32,

    pub fn solve(
        allocator: std.mem.Allocator,
        diagram: *const parser.FlowchartDiagram,
        options: LayoutOptions,
    ) !FlowchartLayout {
        inline for (.{ "font_size", "node_height", "max_label_width", "parallel_spacing", "self_loop_spacing" }) |field| {
            const value = @field(options, field);
            if (!std.math.isFinite(value) or value <= 0) return error.InvalidOptions;
        }
        inline for (.{ "node_padding_x", "node_padding_y", "node_spacing", "layer_spacing", "margin_x", "margin_y" }) |field| {
            const value = @field(options, field);
            if (!std.math.isFinite(value) or value < 0) return error.InvalidOptions;
        }
        if (diagram.nodes.items.len > std.math.maxInt(u16)) return error.LimitExceeded;
        const font = font_mod.Font.init(options.font_size);

        var g = graph_mod.DirectedGraph.init();
        errdefer g.deinit(allocator);

        // 1. Add all nodes to DirectedGraph with measured bounds
        for (diagram.nodes.items) |n| {
            const text = try font.wrapText(allocator, n.label, options.max_label_width);
            defer allocator.free(text.lines);
            var node_w = @max(70.0, text.width + options.node_padding_x * 2.0);
            var node_h = @max(options.node_height, text.height + options.node_padding_y * 2.0);

            switch (n.shape) {
                .rhombus => {
                    node_w *= 2.0;
                    node_h *= 2.0;
                },
                .circle => {
                    const dia = @sqrt(node_w * node_w + node_h * node_h);
                    node_w = dia;
                    node_h = dia;
                },
                .hexagon => {
                    node_w += 24.0;
                },
                else => {},
            }

            const n_id = try g.addNode(allocator, n.id_name);
            g.nodes.items[n_id].width = node_w;
            g.nodes.items[n_id].height = node_h;
        }

        // Self-links are drawn outside their node and do not constrain ranks.
        const link_indices = try allocator.alloc(usize, diagram.links.items.len);
        errdefer allocator.free(link_indices);
        var route_padding: f32 = 0;
        for (diagram.links.items, 0..) |lnk, link_index| {
            if (lnk.from >= diagram.nodes.items.len or lnk.to >= diagram.nodes.items.len) return error.InvalidDiagram;
            if (lnk.from == lnk.to) {
                var count: usize = 0;
                for (diagram.links.items) |other| if (other.from == lnk.from and other.to == lnk.to) {
                    count += 1;
                };
                route_padding = @max(route_padding, @as(f32, @floatFromInt(count)) * options.self_loop_spacing + font.stringWidth(lnk.text) / 2.0);
                continue;
            }
            const id = try g.addEdge(allocator, lnk.from, lnk.to, "");
            link_indices[id] = link_index;
            const lane = parallelLane(diagram, link_index, font, options.parallel_spacing);
            route_padding = @max(route_padding, @abs(lane.offset) + lane.label_width / 2.0);
        }

        // 3. Remove cycles to ensure DAG
        try g.breakCycles(allocator);

        // 4. Assign ranks & proper layering with dummy nodes
        var layered = try layering_mod.assignRanksAndLayers(allocator, &g);
        errdefer layered.deinit(allocator);

        // 5. Minimize crossings via Barycenter heuristic
        try crossing_mod.minimizeCrossings(allocator, &layered, options.crossing_iterations);

        // 6. Coordinate Assignment
        const is_horizontal = (diagram.direction == .left_to_right or diagram.direction == .right_to_left);

        // Step 6a: Assign layer-dependent coordinates (Y for TD, X for LR)
        var max_cross_dim: f32 = 0;
        var cur_main: f32 = if (is_horizontal) options.margin_x else options.margin_y;

        for (0..layered.num_layers) |l_idx| {
            var layer_max_main: f32 = 0;
            var layer_cross_dim: f32 = 0;

            for (layered.layers[l_idx].items) |n_id| {
                const n_node = &g.nodes.items[n_id];
                if (!n_node.is_dummy) {
                    const m_dim = if (is_horizontal) n_node.width else n_node.height;
                    const c_dim = if (is_horizontal) n_node.height else n_node.width;
                    if (m_dim > layer_max_main) layer_max_main = m_dim;
                    layer_cross_dim += c_dim + options.node_spacing;
                } else {
                    layer_cross_dim += 20.0 + options.node_spacing;
                }
            }

            if (layer_max_main == 0) layer_max_main = 20.0;
            if (layer_cross_dim > max_cross_dim) max_cross_dim = layer_cross_dim;

            const center_main = cur_main + layer_max_main / 2.0;

            for (layered.layers[l_idx].items) |n_id| {
                if (is_horizontal) {
                    g.nodes.items[n_id].x = center_main;
                } else {
                    g.nodes.items[n_id].y = center_main;
                }
            }

            cur_main += layer_max_main + options.layer_spacing;
        }

        const total_main = cur_main - options.layer_spacing + (if (is_horizontal) options.margin_x else options.margin_y);

        // Step 6b: Assign cross-axis coordinates (X for TD, Y for LR)
        for (0..layered.num_layers) |l_idx| {
            var cur_cross: f32 = route_padding + (if (is_horizontal) options.margin_y else options.margin_x);

            for (layered.layers[l_idx].items) |n_id| {
                const n_node = &g.nodes.items[n_id];
                const c_dim = if (n_node.is_dummy) 20.0 else (if (is_horizontal) n_node.height else n_node.width);
                const center_cross = cur_cross + c_dim / 2.0;

                if (is_horizontal) {
                    n_node.y = center_cross;
                } else {
                    n_node.x = center_cross;
                }

                cur_cross += c_dim + options.node_spacing;
            }
        }

        // Align layers relative to center
        var max_cross: f32 = 0;
        for (g.nodes.items) |n| {
            const cross_end = if (is_horizontal) n.y + n.height / 2.0 else n.x + n.width / 2.0;
            if (cross_end > max_cross) max_cross = cross_end;
        }

        const total_cross = max_cross + route_padding + (if (is_horizontal) options.margin_y else options.margin_x);

        const total_w = if (is_horizontal) total_main else total_cross;
        const total_h = if (is_horizontal) total_cross else total_main;

        // Invert for BT or RL if requested
        if (diagram.direction == .bottom_to_top) {
            for (g.nodes.items) |*n| {
                n.y = total_h - n.y;
            }
        } else if (diagram.direction == .right_to_left) {
            for (g.nodes.items) |*n| {
                n.x = total_w - n.x;
            }
        }

        return .{
            .diagram = diagram,
            .options = options,
            .font = font,
            .graph = g,
            .link_indices = link_indices,
            .layered = layered,
            .total_width = @max(160.0, total_w),
            .total_height = @max(120.0, total_h),
        };
    }

    pub fn deinit(self: *FlowchartLayout, allocator: std.mem.Allocator) void {
        self.layered.deinit(allocator);
        self.graph.deinit(allocator);
        allocator.free(self.link_indices);
    }

    pub fn renderSvg(self: *const FlowchartLayout, allocator: std.mem.Allocator) ![]u8 {
        var svg = svg_mod.SvgWriter.init(allocator);
        errdefer svg.deinit();
        try self.draw(.{ .allocator = allocator, .sink = &svg });
        return svg.toOwnedSlice();
    }

    /// Emit the same geometry to an SVG writer or another typed drawing sink.
    /// The sink must copy borrowed strings/points before each call returns.
    pub fn draw(self: *const FlowchartLayout, input: anytype) !void {
        const allocator: std.mem.Allocator = input.allocator;
        const svg = input.sink;

        try svg.startSvg(self.total_width, self.total_height);
        try svg.writeStandardDefs();

        const is_horizontal = (self.diagram.direction == .left_to_right or self.diagram.direction == .right_to_left);

        // 1. Render Subgraph boundaries (if any)
        if (self.diagram.subgraphs.items.len > 0) {
            try svg.startGroup("zig-diagram-subgraphs");
            for (self.diagram.subgraphs.items) |sg| {
                try svg.entity(.{ .kind = .flow_subgraph, .name = sg.name });
                var min_x: f32 = std.math.floatMax(f32);
                var min_y: f32 = std.math.floatMax(f32);
                var max_x: f32 = -std.math.floatMax(f32);
                var max_y: f32 = -std.math.floatMax(f32);
                var has_nodes = false;

                for (self.diagram.nodes.items, 0..) |pn, idx| {
                    if (pn.subgraph_id == sg.id and idx < self.graph.nodes.items.len) {
                        const gn = self.graph.nodes.items[idx];
                        has_nodes = true;
                        min_x = @min(min_x, gn.x - gn.width / 2.0);
                        min_y = @min(min_y, gn.y - gn.height / 2.0);
                        max_x = @max(max_x, gn.x + gn.width / 2.0);
                        max_y = @max(max_y, gn.y + gn.height / 2.0);
                    }
                }

                if (has_nodes) {
                    const pad: f32 = 18.0;
                    const header_h: f32 = 24.0;
                    const box_x = min_x - pad;
                    const box_y = min_y - pad - header_h;
                    const box_w = (max_x - min_x) + pad * 2.0;
                    const box_h = (max_y - min_y) + pad * 2.0 + header_h;

                    try svg.rect(box_x, box_y, box_w, box_h, 6.0, 6.0, "zig-diagram-subgraph-box");
                    try svg.textSingleLine(box_x + 12.0, box_y + 16.0, .start, "zig-diagram-subgraph-label", sg.title);
                }
            }
            try svg.endGroup();
        }

        // 2. Render Edges with smooth Bézier splines
        try svg.startGroup("zig-diagram-edges");
        for (self.graph.edges.items) |e| {
            const original_index = e.orig_edge orelse e.id;
            const link_index = self.link_indices[original_index];
            var segment_key: [48]u8 = undefined;
            const segment_name: []const u8 = if (e.id == original_index) "" else try std.fmt.bufPrint(&segment_key, "segment-{d}", .{e.id});
            try svg.entity(.{ .kind = .flow_edge, .index = @as(u32, @intCast(link_index)), .name = segment_name });
            const u = self.graph.nodes.items[e.source];
            const v = self.graph.nodes.items[e.target];
            const reversed = self.graph.edges.items[original_index].reversed;
            const forward = self.diagram.direction == .top_to_bottom or self.diagram.direction == .left_to_right;
            const sign: f32 = if (forward) 1 else -1;

            var x1: f32 = undefined;
            var y1: f32 = undefined;
            var x2: f32 = undefined;
            var y2: f32 = undefined;

            if (is_horizontal) {
                x1 = if (u.is_dummy) u.x else u.x + sign * u.width / 2.0;
                y1 = u.y;
                x2 = if (v.is_dummy) v.x else v.x - sign * v.width / 2.0;
                y2 = v.y;
            } else {
                x1 = u.x;
                y1 = if (u.is_dummy) u.y else u.y + sign * u.height / 2.0;
                x2 = v.x;
                y2 = if (v.is_dummy) v.y else v.y - sign * v.height / 2.0;
            }

            // Arrow marker only on final segment entering a real node
            var arrow_marker: ?[]const u8 = null;
            var line_class: []const u8 = "zig-diagram-edge-line";

            // Original link indices survive cycle breaking and dummy insertion.
            const link = self.diagram.links.items[link_index];
            line_class = switch (link.stroke) {
                .dotted => "zig-diagram-edge-line zig-diagram-edge-dotted",
                .thick => "zig-diagram-edge-line zig-diagram-edge-thick",
                .solid => "zig-diagram-edge-line",
            };
            if (if (reversed) !u.is_dummy else !v.is_dummy) {
                arrow_marker = switch (link.head) {
                    .arrow => "arrow",
                    .circle => "circle",
                    .cross => "cross",
                    .none => null,
                };
            }
            if (reversed) {
                std.mem.swap(f32, &x1, &x2);
                std.mem.swap(f32, &y1, &y2);
            }

            const lane = parallelLane(self.diagram, link_index, self.font, self.options.parallel_spacing);
            // Parallel logical links receive separate curves and label lanes.
            var path_d: []u8 = undefined;
            if (is_horizontal) {
                const mid_x = (x1 + x2) / 2.0;
                path_d = try std.fmt.allocPrint(
                    allocator,
                    "M {d:.1} {d:.1} C {d:.1} {d:.1}, {d:.1} {d:.1}, {d:.1} {d:.1}",
                    .{ x1, y1, mid_x, y1 + lane.offset, mid_x, y2 + lane.offset, x2, y2 },
                );
            } else {
                const mid_y = (y1 + y2) / 2.0;
                path_d = try std.fmt.allocPrint(
                    allocator,
                    "M {d:.1} {d:.1} C {d:.1} {d:.1}, {d:.1} {d:.1}, {d:.1} {d:.1}",
                    .{ x1, y1, x1 + lane.offset, mid_y, x2 + lane.offset, mid_y, x2, y2 },
                );
            }
            defer allocator.free(path_d);

            try svg.path(path_d, line_class, arrow_marker);

            // Edge label
            if (link.text.len > 0 and (if (reversed) !u.is_dummy else !v.is_dummy)) {
                const lbl_x = (x1 + x2) / 2.0 + (if (is_horizontal) @as(f32, 0) else lane.offset * 0.75);
                const lbl_y = (y1 + y2) / 2.0 - 4.0 + (if (is_horizontal) lane.offset * 0.75 else @as(f32, 0));
                try svg.textSingleLine(lbl_x, lbl_y, .middle, "zig-diagram-edge-label", link.text);
            }
        }
        for (self.diagram.links.items, 0..) |link, link_index| {
            if (link.from != link.to) continue;
            try svg.entity(.{ .kind = .flow_edge, .index = @as(u32, @intCast(link_index)) });
            const node = self.graph.nodes.items[link.from];
            var ordinal: usize = 0;
            for (self.diagram.links.items[0..link_index]) |earlier| if (earlier.from == link.from and earlier.to == link.to) {
                ordinal += 1;
            };
            const extent = @as(f32, @floatFromInt(ordinal + 1)) * self.options.self_loop_spacing;
            var bytes: [512]u8 = undefined;
            const d = if (is_horizontal)
                try std.fmt.bufPrint(&bytes, "M {d:.1} {d:.1} C {d:.1} {d:.1}, {d:.1} {d:.1}, {d:.1} {d:.1}", .{ node.x - node.width / 4, node.y + node.height / 2, node.x - node.width / 4, node.y + node.height / 2 + extent, node.x + node.width / 4, node.y + node.height / 2 + extent, node.x + node.width / 4, node.y + node.height / 2 })
            else
                try std.fmt.bufPrint(&bytes, "M {d:.1} {d:.1} C {d:.1} {d:.1}, {d:.1} {d:.1}, {d:.1} {d:.1}", .{ node.x + node.width / 2, node.y - node.height / 4, node.x + node.width / 2 + extent, node.y - node.height / 4, node.x + node.width / 2 + extent, node.y + node.height / 4, node.x + node.width / 2, node.y + node.height / 4 });
            const marker: ?[]const u8 = switch (link.head) {
                .arrow => "arrow",
                .circle => "circle",
                .cross => "cross",
                .none => null,
            };
            const class = switch (link.stroke) {
                .solid => "zig-diagram-edge-line",
                .dotted => "zig-diagram-edge-line zig-diagram-edge-dotted",
                .thick => "zig-diagram-edge-line zig-diagram-edge-thick",
            };
            try svg.path(d, class, marker);
            if (link.text.len > 0) try svg.textSingleLine(node.x + (if (is_horizontal) @as(f32, 0) else node.width / 2 + extent * 0.75), node.y + (if (is_horizontal) node.height / 2 + extent * 0.75 else @as(f32, -4)), .middle, "zig-diagram-edge-label", link.text);
        }
        try svg.endGroup();

        // 3. Render Nodes with shapes and labels
        try svg.startGroup("zig-diagram-nodes");
        for (self.diagram.nodes.items, 0..) |pn, idx| {
            if (idx >= self.graph.nodes.items.len) break;
            try svg.entity(.{ .kind = .flow_node, .name = pn.id_name });
            const gn = self.graph.nodes.items[idx];
            if (gn.is_dummy) continue;

            const w = gn.width;
            const h = gn.height;
            const x = gn.x;
            const y = gn.y;
            const left = x - w / 2.0;
            const top = y - h / 2.0;

            switch (pn.shape) {
                .rectangle => {
                    try svg.rect(left, top, w, h, 2.0, 2.0, "zig-diagram-node-box");
                },
                .rounded_rectangle => {
                    try svg.rect(left, top, w, h, 8.0, 8.0, "zig-diagram-node-box");
                },
                .stadium => {
                    try svg.rect(left, top, w, h, h / 2.0, h / 2.0, "zig-diagram-node-box");
                },
                .circle => {
                    try svg.circle(x, y, @max(w, h) / 2.0, "zig-diagram-node-box");
                },
                .rhombus => {
                    const pts = [_][2]f32{
                        .{ x, top },
                        .{ left + w, y },
                        .{ x, top + h },
                        .{ left, y },
                    };
                    try svg.polygon(&pts, "zig-diagram-node-box");
                },
                .hexagon => {
                    const inset: f32 = 12.0;
                    const pts = [_][2]f32{
                        .{ left + inset, top },
                        .{ left + w - inset, top },
                        .{ left + w, y },
                        .{ left + w - inset, top + h },
                        .{ left + inset, top + h },
                        .{ left, y },
                    };
                    try svg.polygon(&pts, "zig-diagram-node-box");
                },
                .parallelogram => {
                    const skew: f32 = 12.0;
                    const pts = [_][2]f32{
                        .{ left + skew, top },
                        .{ left + w, top },
                        .{ left + w - skew, top + h },
                        .{ left, top + h },
                    };
                    try svg.polygon(&pts, "zig-diagram-node-box");
                },
                .trapezoid => {
                    const inset: f32 = 12.0;
                    const pts = [_][2]f32{
                        .{ left + inset, top },
                        .{ left + w - inset, top },
                        .{ left + w, top + h },
                        .{ left, top + h },
                    };
                    try svg.polygon(&pts, "zig-diagram-node-box");
                },
                .cylinder => {
                    // Cylinder shape: top rect with rounded ends
                    try svg.rect(left, top, w, h, 6.0, 6.0, "zig-diagram-node-box");
                },
                .asymmetric => {
                    const arrow_w: f32 = 10.0;
                    const pts = [_][2]f32{
                        .{ left, top },
                        .{ left + w - arrow_w, top },
                        .{ left + w, y },
                        .{ left + w - arrow_w, top + h },
                        .{ left, top + h },
                    };
                    try svg.polygon(&pts, "zig-diagram-node-box");
                },
            }

            const text = try self.font.wrapText(allocator, pn.label, self.options.max_label_width);
            defer allocator.free(text.lines);
            for (text.lines, 0..) |line, line_index| {
                const baseline = if (text.lines.len == 1) y + 5 else y - text.height / 2 + self.font.baselineOffset() + @as(f32, @floatFromInt(line_index)) * self.font.lineHeight();
                try svg.textSingleLine(x, baseline, .middle, "zig-diagram-label", line.text);
            }
        }
        try svg.endGroup();

        try svg.endSvg();
    }
};

const Lane = struct { offset: f32, label_width: f32 };
fn parallelLane(diagram: *const parser.FlowchartDiagram, index: usize, font: font_mod.Font, spacing: f32) Lane {
    const link = diagram.links.items[index];
    var count: usize = 0;
    var ordinal: usize = 0;
    var label_width: f32 = 0;
    for (diagram.links.items, 0..) |other, other_index| {
        if ((other.from == link.from and other.to == link.to) or (other.from == link.to and other.to == link.from)) {
            count += 1;
            if (other_index < index) ordinal += 1;
            label_width = @max(label_width, font.stringWidth(other.text));
        }
    }
    if (count < 2) return .{ .offset = 0, .label_width = label_width };
    const distance = @max(spacing, (label_width + 16) / 0.75);
    return .{ .offset = (@as(f32, @floatFromInt(ordinal)) - @as(f32, @floatFromInt(count - 1)) / 2) * distance, .label_width = label_width };
}

test "flowchart layout solves coordinates and produces valid SVG" {
    const src =
        \\graph TD
        \\  Start[Start Processing] --> Ready{Is Ready?}
        \\  Ready -->|Yes| Go([Proceed Now])
        \\  Ready -. No .-> Stop((Halt))
        \\  Go ==> Done{{Completed}}
        \\  Stop --- Done
    ;

    var diag = try parser.parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    var layout = try FlowchartLayout.solve(std.testing.allocator, &diag, .{});
    defer layout.deinit(std.testing.allocator);

    try std.testing.expect(layout.total_width > 100.0);
    try std.testing.expect(layout.total_height > 100.0);

    const svg_out = try layout.renderSvg(std.testing.allocator);
    defer std.testing.allocator.free(svg_out);

    try std.testing.expect(std.mem.indexOf(u8, svg_out, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Start Processing") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Is Ready?") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Proceed Now") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zig-diagram-node-box") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zig-diagram-edge-line") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "</svg>") != null);
}

test "flowchart layout handles LR horizontal orientation with subgraphs" {
    const src =
        \\flowchart LR
        \\  subgraph Pipeline [Build Pipeline]
        \\    Build[Compile] --> Test[Run Tests]
        \\  end
        \\  Deploy([Deploy Prod])
        \\  Test --> Deploy
    ;

    var diag = try parser.parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    var layout = try FlowchartLayout.solve(std.testing.allocator, &diag, .{});
    defer layout.deinit(std.testing.allocator);

    const svg_out = try layout.renderSvg(std.testing.allocator);
    defer std.testing.allocator.free(svg_out);

    try std.testing.expect(std.mem.indexOf(u8, svg_out, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Build Pipeline") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Compile") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Run Tests") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Deploy Prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zig-diagram-subgraph-box") != null);
}
