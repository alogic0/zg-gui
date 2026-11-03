//! Zig Mermaid Viewer & Diagram Typesetter
//!
//! A native, local-first diagram rendering engine in pure Zig.
const std = @import("std");

pub const version = "0.9.0";

pub const font_metrics = @import("font_metrics.zig");
pub const Font = font_metrics.Font;

pub const drawing = @import("drawing.zig");
pub const Scene = drawing.Scene;
pub const svg = @import("svg.zig");
pub const SvgWriter = svg.SvgWriter;

pub const graph = @import("graph.zig");
pub const DirectedGraph = graph.DirectedGraph;

pub const sequence_parser = @import("sequence_parser.zig");
pub const SequenceDiagram = sequence_parser.SequenceDiagram;

pub const sequence_layout = @import("sequence_layout.zig");
pub const SequenceLayout = sequence_layout.SequenceLayout;

pub const flowchart_parser = @import("flowchart_parser.zig");
pub const FlowchartDiagram = flowchart_parser.FlowchartDiagram;

pub const sugiyama_layering = @import("sugiyama_layering.zig");
pub const LayeredGraph = sugiyama_layering.LayeredGraph;

pub const sugiyama_crossing = @import("sugiyama_crossing.zig");
pub const minimizeCrossings = sugiyama_crossing.minimizeCrossings;

pub const sugiyama_layout = @import("sugiyama_layout.zig");
pub const FlowchartLayout = sugiyama_layout.FlowchartLayout;

pub const DiagramError = error{
    EmptyDiagram,
    UnsupportedDiagramType,
    InvalidSyntax,
    OutOfMemory,
    WriteFailed,
};

/// High-level API: Takes raw Mermaid text source and produces clean, valid SVG markup.
pub fn renderDiagramToSvg(allocator: std.mem.Allocator, source: []const u8) DiagramError![]u8 {
    const trimmed = std.mem.trimStart(u8, source, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyDiagram;

    if (std.mem.startsWith(u8, trimmed, "sequenceDiagram")) {
        var diag = sequence_parser.parse(allocator, trimmed) catch |err| switch (err) {
            error.EmptyDiagram => return error.EmptyDiagram,
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidHeader, error.InvalidSyntax, error.UnknownParticipant => return error.InvalidSyntax,
        };
        defer diag.deinit(allocator);

        var layout = sequence_layout.SequenceLayout.solve(allocator, &diag, .{}) catch |err| switch (err) {
            error.InvalidOptions, error.InvalidDiagram, error.LimitExceeded => return error.InvalidSyntax,
            error.EmptyDiagram => return error.EmptyDiagram,
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer layout.deinit(allocator);

        return layout.renderSvg(allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.WriteFailed => return error.WriteFailed,
        };
    } else if (std.mem.startsWith(u8, trimmed, "graph ") or std.mem.startsWith(u8, trimmed, "flowchart ")) {
        var diag = flowchart_parser.parse(allocator, trimmed) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer diag.deinit(allocator);

        var layout = sugiyama_layout.FlowchartLayout.solve(allocator, &diag, .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.GraphHasCycles, error.InvalidOptions, error.InvalidDiagram, error.LimitExceeded => return error.InvalidSyntax,
        };
        defer layout.deinit(allocator);

        return layout.renderSvg(allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.WriteFailed, error.NoSpaceLeft => return error.WriteFailed,
        };
    }

    return error.UnsupportedDiagramType;
}

pub const SceneLimits = struct {
    max_source_bytes: usize = 32 * 1024,
    max_nodes: usize = 128,
    max_edges: usize = 256,
    drawing: drawing.Limits = .{},
};

/// Build an owned scene. Use a bounded allocator to also cap parsing/layout
/// scratch and arena growth. Errors release the candidate without publishing it.
pub fn buildScene(input: struct { allocator: std.mem.Allocator, source: []const u8, limits: SceneLimits = .{} }) !Scene {
    if (input.source.len > input.limits.max_source_bytes) return error.LimitExceeded;
    const source = std.mem.trimStart(u8, input.source, " \t\r\n");
    if (source.len == 0) return error.EmptyDiagram;
    var sink = drawing.Builder.init(.{ .allocator = input.allocator, .limits = input.limits.drawing });
    errdefer sink.scene.deinit();
    if (std.mem.startsWith(u8, source, "sequenceDiagram")) {
        var diagram = try sequence_parser.parse(input.allocator, source);
        defer diagram.deinit(input.allocator);
        if (diagram.participants.items.len > input.limits.max_nodes or diagram.events.items.len > input.limits.max_edges) return error.LimitExceeded;
        var layout = try SequenceLayout.solve(input.allocator, &diagram, .{});
        defer layout.deinit(input.allocator);
        try layout.draw(.{ .allocator = input.allocator, .sink = &sink });
    } else if (std.mem.startsWith(u8, source, "graph ") or std.mem.startsWith(u8, source, "flowchart ")) {
        var diagram = try flowchart_parser.parse(input.allocator, source);
        defer diagram.deinit(input.allocator);
        if (diagram.nodes.items.len == 0) return error.EmptyDiagram;
        if (diagram.nodes.items.len > input.limits.max_nodes or diagram.links.items.len > input.limits.max_edges) return error.LimitExceeded;
        var layout = try FlowchartLayout.solve(input.allocator, &diagram, .{});
        defer layout.deinit(input.allocator);
        try layout.draw(.{ .allocator = input.allocator, .sink = &sink });
    } else return error.UnsupportedDiagramType;
    return sink.scene;
}

test {
    _ = @import("font_metrics.zig");
    _ = @import("svg.zig");
    _ = @import("graph.zig");
    _ = @import("sequence_parser.zig");
    _ = @import("sequence_layout.zig");
    _ = @import("flowchart_parser.zig");
    _ = @import("sugiyama_layering.zig");
    _ = @import("sugiyama_crossing.zig");
    _ = @import("sugiyama_layout.zig");
}

test "root sanity check" {
    try std.testing.expect(version.len > 0);
}

test "renderDiagramToSvg end-to-end integration" {
    const seq_src =
        \\sequenceDiagram
        \\  Alice->>Bob: Hello Bob
        \\  Bob-->>Alice: Hi Alice
    ;
    const seq_svg = try renderDiagramToSvg(std.testing.allocator, seq_src);
    defer std.testing.allocator.free(seq_svg);
    try std.testing.expect(std.mem.indexOf(u8, seq_svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, seq_svg, "Hello Bob") != null);

    const flow_src =
        \\graph TD
        \\  A[Step 1] --> B{Step 2}
        \\  B -->|OK| C([Done])
    ;
    const flow_svg = try renderDiagramToSvg(std.testing.allocator, flow_src);
    defer std.testing.allocator.free(flow_svg);
    try std.testing.expect(std.mem.indexOf(u8, flow_svg, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, flow_svg, "Step 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, flow_svg, "Done") != null);

    // Unsupported diagram returns error
    try std.testing.expectError(error.UnsupportedDiagramType, renderDiagramToSvg(std.testing.allocator, "classDiagram\n  class A"));
}

test "owned drawing scenes replay exact flowchart and sequence SVG" {
    for ([_][]const u8{
        "flowchart LR\n subgraph Pipeline [Build Pipeline]\n A[Compile] --> B{Check}\n end\n B --> C((Done))",
        "sequenceDiagram\n autonumber\n title Example\n participant Client\n participant Server\n Client->>+Server: Request\n Note over Server: Work\n Server-->>-Client: Reply\n Client->>Client: Self",
    }) |source| {
        const direct = try renderDiagramToSvg(std.testing.allocator, source);
        defer std.testing.allocator.free(direct);
        const mutable_source = try std.testing.allocator.dupe(u8, source);
        var scene = try buildScene(.{ .allocator = std.testing.allocator, .source = mutable_source });
        defer scene.deinit();
        @memset(mutable_source, 'x');
        std.testing.allocator.free(mutable_source);
        const replay = try scene.renderSvg(std.testing.allocator);
        defer std.testing.allocator.free(replay);
        try std.testing.expectEqualStrings(direct, replay);
        try std.testing.expect(scene.elements.items.len > 0);
        for (scene.elements.items, 0..) |element, i| {
            for (scene.elements.items[0..i]) |other| try std.testing.expect(!element.key.eql(other.key));
        }
    }
}

test "source-named primitive identities survive source reordering and label changes" {
    var a = try buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n A[One]\n B[Two]\n A --> B" });
    defer a.deinit();
    var b = try buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n B[Updated]\n A[One]\n A --> B" });
    defer b.deinit();
    var matches: usize = 0;
    for (a.elements.items) |left| {
        if (left.key.entity.kind != .flow_node) continue;
        for (b.elements.items) |right| if (left.key.eql(right.key)) {
            matches += 1;
        };
    }
    try std.testing.expectEqual(@as(usize, 4), matches);
}

test "scene admission rejects empty unsupported and bounded inputs" {
    const a = std.testing.allocator;
    try std.testing.expectError(error.EmptyDiagram, buildScene(.{ .allocator = a, .source = " \n" }));
    try std.testing.expectError(error.EmptyDiagram, buildScene(.{ .allocator = a, .source = "graph TD\n" }));
    try std.testing.expectError(error.UnsupportedDiagramType, buildScene(.{ .allocator = a, .source = "classDiagram" }));
    const source = "graph TD\n A --> B";
    try std.testing.expectError(error.LimitExceeded, buildScene(.{ .allocator = a, .source = source, .limits = .{ .max_source_bytes = 1 } }));
    try std.testing.expectError(error.LimitExceeded, buildScene(.{ .allocator = a, .source = source, .limits = .{ .max_nodes = 1 } }));
    try std.testing.expectError(error.LimitExceeded, buildScene(.{ .allocator = a, .source = source, .limits = .{ .max_edges = 0 } }));
    try std.testing.expectError(error.LimitExceeded, buildScene(.{ .allocator = a, .source = source, .limits = .{ .drawing = .{ .max_elements = 1 } } }));
    try std.testing.expectError(error.LimitExceeded, buildScene(.{ .allocator = a, .source = source, .limits = .{ .drawing = .{ .max_data_bytes = 1 } } }));
    var bytes: [128]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&bytes);
    try std.testing.expectError(error.OutOfMemory, buildScene(.{ .allocator = fixed.allocator(), .source = source }));
}

fn sceneAllocationProbe(allocator: std.mem.Allocator) !void {
    for ([_][]const u8{ "graph TD\n A[A longer label with several words to wrap without losing any content] --> B{Two}\n B --> C\n A --> C\n D --> B\n A --> A\n A -->|second| B", "sequenceDiagram\n A->>+B: Hello\n Note over B: Work\n B-->>-A: Bye\n activate A" }) |source| {
        var scene = try buildScene(.{ .allocator = allocator, .source = source });
        defer scene.deinit();
        const output = scene.renderSvg(allocator) catch |err| switch (err) {
            error.WriteFailed => return error.OutOfMemory,
            else => return err,
        };
        defer allocator.free(output);
    }
}

test "scene capture and replay release every allocation after failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, sceneAllocationProbe, .{});
}

test "sequence activation primitives precede notes and message labels" {
    var scene = try buildScene(.{ .allocator = std.testing.allocator, .source = "sequenceDiagram\n A->>+B: Request\n Note over B: Keep this visible\n B-->>-A: Reply" });
    defer scene.deinit();
    var activation: ?usize = null;
    var note: ?usize = null;
    for (scene.elements.items, 0..) |element, index| {
        if (std.mem.eql(u8, element.class, "zig-diagram-activation")) activation = index;
        if (std.mem.eql(u8, element.class, "zig-diagram-note-box")) note = index;
    }
    try std.testing.expect(activation != null and note != null);
    try std.testing.expect(activation.? < note.?);
}

test "flow links retain original arrow direction through cycle breaking and inverted ranks" {
    const a = std.testing.allocator;
    for ([_][]const u8{ "TD", "BT", "LR", "RL" }) |direction| {
        const source = try std.fmt.allocPrint(a, "graph {s}\n A[One] --> B[Two]\n B --> A", .{direction});
        defer a.free(source);
        var diagram = try flowchart_parser.parse(a, source);
        defer diagram.deinit(a);
        var layout = try FlowchartLayout.solve(a, &diagram, .{});
        defer layout.deinit(a);
        var sink = drawing.Builder.init(.{ .allocator = a });
        defer sink.scene.deinit();
        try layout.draw(.{ .allocator = a, .sink = &sink });
        var links: usize = 0;
        for (sink.scene.elements.items) |element| {
            if (element.shape != .path) continue;
            const index = element.key.entity.index;
            const edge = layout.graph.edges.items[index];
            const link = diagram.links.items[index];
            const from = layout.graph.nodes.items[link.from];
            const horizontal = diagram.direction == .left_to_right or diagram.direction == .right_to_left;
            const forward = diagram.direction == .top_to_bottom or diagram.direction == .left_to_right;
            const sign: f32 = (if (forward) @as(f32, 1) else -1) * (if (edge.reversed) @as(f32, -1) else 1);
            const x = from.x + (if (horizontal) sign * from.width / 2 else 0);
            const y = from.y + (if (horizontal) 0 else sign * from.height / 2);
            var prefix: [128]u8 = undefined;
            const expected = try std.fmt.bufPrint(&prefix, "M {d:.1} {d:.1} C", .{ x, y });
            try std.testing.expect(std.mem.startsWith(u8, element.shape.path.d, expected));
            try std.testing.expectEqualStrings("arrow", element.shape.path.marker_end.?);
            links += 1;
        }
        try std.testing.expectEqual(@as(usize, 2), links);
    }
}

test "flowchart self-links parallel routes and long labels remain explicit" {
    const source =
        \\flowchart TD
        \\  Read[Read a detailed source document with enough words to exercise wrapping across several separate lines]
        \\  Check{Validate all required fields and decide whether this item is ready for the next processing stage}
        \\  Save[Save the final result]
        \\  Read -->|first pass| Check
        \\  Read -->|second pass| Check
        \\  Check -->|retry| Read
        \\  Check -->|repeat| Check
        \\  Check --> Save
        \\  Read -->|skip intermediate steps| Save
    ;
    const a = std.testing.allocator;
    var diagram = try flowchart_parser.parse(a, source);
    defer diagram.deinit(a);
    var layout = try FlowchartLayout.solve(a, &diagram, .{});
    defer layout.deinit(a);
    var scene = try buildScene(.{ .allocator = a, .source = source });
    defer scene.deinit();
    var labels: usize = 0;
    var first: ?[]const u8 = null;
    var second: ?[]const u8 = null;
    var edge_labels: usize = 0;
    for (scene.elements.items) |element| {
        if (element.key.entity.kind == .flow_node and std.mem.eql(u8, element.key.entity.name, "Read") and element.shape == .text) labels += 1;
        if (element.shape == .path and element.key.entity.kind == .flow_edge) {
            if (element.key.entity.index == 0) first = element.shape.path.d;
            if (element.key.entity.index == 1) second = element.shape.path.d;
        }
        if (element.shape == .text and std.mem.eql(u8, element.shape.text.content, "skip intermediate steps")) edge_labels += 1;
        if (element.shape == .text) {
            const t = element.shape.text;
            try std.testing.expect(t.x >= 0 and t.x <= scene.width and t.y >= 0 and t.y <= scene.height);
        }
    }
    try std.testing.expect(labels >= 2);
    try std.testing.expect(first != null and second != null and !std.mem.eql(u8, first.?, second.?));
    try std.testing.expectEqual(@as(usize, 1), edge_labels);
    const direct = try renderDiagramToSvg(a, source);
    defer a.free(direct);
    const replay = try scene.renderSvg(a);
    defer a.free(replay);
    try std.testing.expectEqualStrings(direct, replay);
    var loop = try buildScene(.{ .allocator = a, .source = "graph LR\n A[Only node] -->|again| A" });
    defer loop.deinit();
    try std.testing.expect(loop.elements.items[0].shape == .path);
    try std.testing.expectEqualStrings("arrow", loop.elements.items[0].shape.path.marker_end.?);
}

test "larger workflow layout has disjoint nodes bounded output and no lost edge labels" {
    const a = std.testing.allocator;
    var source = std.Io.Writer.Allocating.init(a);
    defer source.deinit();
    try source.writer.writeAll("graph LR\n");
    for (0..72) |i| try source.writer.print(" N{d}[Stage {d}]\n", .{ i, i });
    for (0..71) |i| try source.writer.print(" N{d} --> N{d}\n", .{ i, i + 1 });
    try source.writer.writeAll(" N0 -->|long transition| N71\n N30 --> N8\n N5 --> N5\n");
    const bytes = source.written();
    var diagram = try flowchart_parser.parse(a, bytes);
    defer diagram.deinit(a);
    var layout = try FlowchartLayout.solve(a, &diagram, .{});
    defer layout.deinit(a);
    for (layout.graph.nodes.items, 0..) |node, i| {
        if (node.is_dummy) continue;
        for (layout.graph.nodes.items[0..i]) |other| {
            if (other.is_dummy) continue;
            const overlap_x = @abs(node.x - other.x) < (node.width + other.width) / 2;
            const overlap_y = @abs(node.y - other.y) < (node.height + other.height) / 2;
            try std.testing.expect(!(overlap_x and overlap_y));
        }
    }
    var storage: [2 * 1024 * 1024]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&storage);
    var scene = try buildScene(.{ .allocator = fixed.allocator(), .source = bytes });
    defer scene.deinit();
    try std.testing.expect(std.math.isFinite(scene.width) and std.math.isFinite(scene.height));
    var count: usize = 0;
    for (scene.elements.items) |element| if (element.shape == .text and std.mem.eql(u8, element.shape.text.content, "long transition")) {
        count += 1;
    };
    try std.testing.expectEqual(@as(usize, 1), count);
    try std.testing.expect(scene.elements.items.len < 2048);
    try std.testing.expectError(error.InvalidOptions, FlowchartLayout.solve(a, &diagram, .{ .parallel_spacing = std.math.nan(f32) }));
}

test "sequence long labels notes and self messages fit their measured scene" {
    const source =
        \\sequenceDiagram
        \\ title A detailed title for a processing workflow with retries and explicit review
        \\ participant Reader as A reader reviewing a detailed source document before processing
        \\ participant Engine as A processing engine with a descriptive participant label
        \\ Reader->>+Engine: Please validate every required field and produce a complete readable report for review
        \\ Note left of Reader: This explanatory note contains enough words to wrap over several lines without escaping its box
        \\ Engine->>Engine: Repeat the local consistency check with all source fields before returning the final result
        \\ Note over Reader,Engine: The review covers both participants and should remain fully visible
        \\ Engine-->>-Reader: Here is a complete result with the original source data preserved
    ;
    var scene = try buildScene(.{ .allocator = std.testing.allocator, .source = source });
    defer scene.deinit();
    var note_lines: usize = 0;
    for (scene.elements.items) |element| switch (element.shape) {
        .rect => |r| try std.testing.expect(r.x >= 0 and r.y >= 0 and r.x + r.width <= scene.width + 0.1 and r.y + r.height <= scene.height + 0.1),
        .text => |t| {
            try std.testing.expect(t.x >= 0 and t.x <= scene.width and t.y >= 0 and t.y <= scene.height);
            if (std.mem.eql(u8, element.class, "zig-diagram-note-text")) note_lines += 1;
        },
        else => {},
    };
    try std.testing.expect(note_lines >= 4);
    const direct = try renderDiagramToSvg(std.testing.allocator, source);
    defer std.testing.allocator.free(direct);
    const replay = try scene.renderSvg(std.testing.allocator);
    defer std.testing.allocator.free(replay);
    try std.testing.expectEqualStrings(direct, replay);
}
