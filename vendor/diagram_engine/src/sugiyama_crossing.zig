//! Sugiyama Phase 3: Crossing minimization.
//! Uses the Barycenter heuristic with alternating bidirectional sweeps to minimize edge crossings.
const std = @import("std");
const graph_mod = @import("graph.zig");
const layering_mod = @import("sugiyama_layering.zig");

const NodeBarycenter = struct {
    node_id: graph_mod.NodeId,
    barycenter: f32,
    original_order: u16,

    pub fn lessThan(_: void, a: NodeBarycenter, b: NodeBarycenter) bool {
        if (a.barycenter != b.barycenter) {
            return a.barycenter < b.barycenter;
        }
        return a.original_order < b.original_order;
    }
};

/// Counts the total number of edge crossings between all adjacent layer pairs.
pub fn countCrossings(allocator: std.mem.Allocator, layered: *const layering_mod.LayeredGraph) !usize {
    if (layered.num_layers <= 1) return 0;
    const g = layered.graph;

    var total_crossings: usize = 0;

    var l: usize = 0;
    while (l < layered.num_layers - 1) : (l += 1) {
        const current_rank: u16 = @intCast(l);
        const next_rank: u16 = @intCast(l + 1);

        // Collect all edges between current_rank and next_rank
        var layer_edges = std.ArrayList(graph_mod.Edge).empty;
        defer layer_edges.deinit(allocator);

        for (g.edges.items) |e| {
            if (g.nodes.items[e.source].rank == current_rank and g.nodes.items[e.target].rank == next_rank) {
                try layer_edges.append(allocator, e);
            }
        }

        const edges = layer_edges.items;
        for (edges, 0..) |e1, i| {
            for (edges[i + 1 ..]) |e2| {
                const src1_order = g.nodes.items[e1.source].order;
                const dst1_order = g.nodes.items[e1.target].order;
                const src2_order = g.nodes.items[e2.source].order;
                const dst2_order = g.nodes.items[e2.target].order;

                if ((src1_order < src2_order and dst1_order > dst2_order) or
                    (src1_order > src2_order and dst1_order < dst2_order))
                {
                    total_crossings += 1;
                }
            }
        }
    }

    return total_crossings;
}

/// Applies the alternating barycenter heuristic to minimize edge crossings.
pub fn minimizeCrossings(
    allocator: std.mem.Allocator,
    layered: *layering_mod.LayeredGraph,
    iterations: usize,
) !void {
    if (layered.num_layers <= 1) return;
    const g = layered.graph;

    // Track best ordering to prevent regressions
    var best_layers = try allocator.alloc([]graph_mod.NodeId, layered.num_layers);
    var best_count: usize = 0;
    defer {
        for (best_layers[0..best_count]) |slice| allocator.free(slice);
        allocator.free(best_layers);
    }

    for (0..layered.num_layers) |l| {
        best_layers[l] = try allocator.dupe(graph_mod.NodeId, layered.layers[l].items);
        best_count += 1;
    }

    var best_crossings = try countCrossings(allocator, layered);
    if (best_crossings == 0) return;

    var iter: usize = 0;
    while (iter < iterations) : (iter += 1) {
        // Downward sweep: layer 1 up to num_layers - 1
        var l: usize = 1;
        while (l < layered.num_layers) : (l += 1) {
            try reorderLayerDownward(allocator, layered, l);
        }

        // Upward sweep: layer num_layers - 2 down to 0
        var up_l: usize = layered.num_layers - 1;
        while (up_l > 0) {
            up_l -= 1;
            try reorderLayerUpward(allocator, layered, up_l);
        }

        const current_crossings = try countCrossings(allocator, layered);
        if (current_crossings < best_crossings) {
            best_crossings = current_crossings;
            for (0..layered.num_layers) |layer_idx| {
                @memcpy(best_layers[layer_idx], layered.layers[layer_idx].items);
            }
            if (best_crossings == 0) break;
        }
    }

    // Restore best ordering
    for (0..layered.num_layers) |layer_idx| {
        @memcpy(layered.layers[layer_idx].items, best_layers[layer_idx]);
        for (layered.layers[layer_idx].items, 0..) |n_id, order_idx| {
            g.nodes.items[n_id].order = @intCast(order_idx);
        }
    }
}

fn reorderLayerDownward(
    allocator: std.mem.Allocator,
    layered: *layering_mod.LayeredGraph,
    layer_idx: usize,
) !void {
    const g = layered.graph;
    const current_layer = &layered.layers[layer_idx];
    const n = current_layer.items.len;
    if (n <= 1) return;

    var barycenters = try allocator.alloc(NodeBarycenter, n);
    defer allocator.free(barycenters);

    for (current_layer.items, 0..) |v_id, i| {
        var sum: f32 = 0;
        var count: f32 = 0;

        for (g.edges.items) |e| {
            if (e.target == v_id and g.nodes.items[e.source].rank == layer_idx - 1) {
                sum += @floatFromInt(g.nodes.items[e.source].order);
                count += 1.0;
            }
        }

        const b = if (count > 0) sum / count else @as(f32, @floatFromInt(i));
        barycenters[i] = .{
            .node_id = v_id,
            .barycenter = b,
            .original_order = @intCast(i),
        };
    }

    std.sort.insertion(NodeBarycenter, barycenters, {}, NodeBarycenter.lessThan);

    for (barycenters, 0..) |nb, new_idx| {
        current_layer.items[new_idx] = nb.node_id;
        g.nodes.items[nb.node_id].order = @intCast(new_idx);
    }
}

fn reorderLayerUpward(
    allocator: std.mem.Allocator,
    layered: *layering_mod.LayeredGraph,
    layer_idx: usize,
) !void {
    const g = layered.graph;
    const current_layer = &layered.layers[layer_idx];
    const n = current_layer.items.len;
    if (n <= 1) return;

    var barycenters = try allocator.alloc(NodeBarycenter, n);
    defer allocator.free(barycenters);

    for (current_layer.items, 0..) |u_id, i| {
        var sum: f32 = 0;
        var count: f32 = 0;

        for (g.edges.items) |e| {
            if (e.source == u_id and g.nodes.items[e.target].rank == layer_idx + 1) {
                sum += @floatFromInt(g.nodes.items[e.target].order);
                count += 1.0;
            }
        }

        const b = if (count > 0) sum / count else @as(f32, @floatFromInt(i));
        barycenters[i] = .{
            .node_id = u_id,
            .barycenter = b,
            .original_order = @intCast(i),
        };
    }

    std.sort.insertion(NodeBarycenter, barycenters, {}, NodeBarycenter.lessThan);

    for (barycenters, 0..) |nb, new_idx| {
        current_layer.items[new_idx] = nb.node_id;
        g.nodes.items[nb.node_id].order = @intCast(new_idx);
    }
}

test "sugiyama crossing minimization untangles crossed edges" {
    var g = graph_mod.DirectedGraph.init();
    defer g.deinit(std.testing.allocator);

    const a = try g.addNode(std.testing.allocator, "A");
    const b = try g.addNode(std.testing.allocator, "B");
    const c = try g.addNode(std.testing.allocator, "C");
    const d = try g.addNode(std.testing.allocator, "D");

    // Intentionally crossed edges:
    // Layer 0: A (0), B (1)
    // Layer 1: C (0), D (1)
    // Edges: A -> D (0 -> 1), B -> C (1 -> 0) => Crossing!
    _ = try g.addEdge(std.testing.allocator, a, d, "");
    _ = try g.addEdge(std.testing.allocator, b, c, "");

    var layered = try layering_mod.assignRanksAndLayers(std.testing.allocator, &g);
    defer layered.deinit(std.testing.allocator);

    // Initial crossing count must be 1
    const initial_crossings = try countCrossings(std.testing.allocator, &layered);
    try std.testing.expectEqual(@as(usize, 1), initial_crossings);

    // Minimize crossings
    try minimizeCrossings(std.testing.allocator, &layered, 4);

    // After minimization, crossings must be 0
    const final_crossings = try countCrossings(std.testing.allocator, &layered);
    try std.testing.expectEqual(@as(usize, 0), final_crossings);

    // Verify ordering: D should now precede C in layer 1, or B should precede A in layer 0
    const u_a = g.nodes.items[a].order;
    const u_b = g.nodes.items[b].order;
    const v_c = g.nodes.items[c].order;
    const v_d = g.nodes.items[d].order;

    // A->D and B->C without crossing means (u_a < u_b and v_d < v_c) or (u_b < u_a and v_c < v_d)
    const valid_unturned = (u_a < u_b and v_d < v_c) or (u_b < u_a and v_c < v_d);
    try std.testing.expect(valid_unturned);
}

test "sugiyama crossing minimization on 3-layer tangled graph" {
    var g = graph_mod.DirectedGraph.init();
    defer g.deinit(std.testing.allocator);

    const a1 = try g.addNode(std.testing.allocator, "A1");
    const a2 = try g.addNode(std.testing.allocator, "A2");
    const a3 = try g.addNode(std.testing.allocator, "A3");

    const b1 = try g.addNode(std.testing.allocator, "B1");
    const b2 = try g.addNode(std.testing.allocator, "B2");
    const b3 = try g.addNode(std.testing.allocator, "B3");

    const c1 = try g.addNode(std.testing.allocator, "C1");
    const c2 = try g.addNode(std.testing.allocator, "C2");

    // Crossings between L0 and L1:
    _ = try g.addEdge(std.testing.allocator, a1, b3, "");
    _ = try g.addEdge(std.testing.allocator, a2, b2, "");
    _ = try g.addEdge(std.testing.allocator, a3, b1, "");

    // Crossings between L1 and L2:
    _ = try g.addEdge(std.testing.allocator, b1, c2, "");
    _ = try g.addEdge(std.testing.allocator, b2, c1, "");
    _ = try g.addEdge(std.testing.allocator, b3, c2, "");

    var layered = try layering_mod.assignRanksAndLayers(std.testing.allocator, &g);
    defer layered.deinit(std.testing.allocator);

    const initial = try countCrossings(std.testing.allocator, &layered);
    try std.testing.expect(initial > 0);

    try minimizeCrossings(std.testing.allocator, &layered, 6);

    const minimized = try countCrossings(std.testing.allocator, &layered);
    try std.testing.expect(minimized < initial);
}
