//! Sugiyama Phase 1 & 2: Rank assignment and proper layering.
//! Assigns vertical/horizontal ranks to DAG nodes and inserts dummy nodes for edges spanning multiple layers.
const std = @import("std");
const graph_mod = @import("graph.zig");

pub const LayeredGraph = struct {
    graph: *graph_mod.DirectedGraph,
    layers: []std.ArrayList(graph_mod.NodeId),
    num_layers: usize,

    pub fn deinit(self: *LayeredGraph, allocator: std.mem.Allocator) void {
        for (self.layers) |*l| {
            l.deinit(allocator);
        }
        allocator.free(self.layers);
    }
};

/// Computes ranks for all nodes in the DAG using longest path layering,
/// inserts virtual dummy nodes so every edge spans exactly 1 rank,
/// and partitions nodes into discrete layers.
pub fn assignRanksAndLayers(
    allocator: std.mem.Allocator,
    g: *graph_mod.DirectedGraph,
) !LayeredGraph {
    const node_count = g.nodes.items.len;
    if (node_count == 0) {
        const empty_layers = try allocator.alloc(std.ArrayList(graph_mod.NodeId), 0);
        return .{
            .graph = g,
            .layers = empty_layers,
            .num_layers = 0,
        };
    }

    // Step 1: Topological sort to process nodes in dependency order
    const topo_order = try g.topologicalSort(allocator);
    defer allocator.free(topo_order);

    // Step 2: Longest-path rank assignment
    var ranks = try allocator.alloc(u16, node_count);
    defer allocator.free(ranks);
    @memset(ranks, 0);

    for (topo_order) |u| {
        const u_rank = ranks[u];
        for (g.edges.items) |e| {
            if (e.source == u) {
                const min_v_rank = u_rank + e.min_len;
                if (min_v_rank > ranks[e.target]) {
                    ranks[e.target] = min_v_rank;
                }
            }
        }
    }

    // Update node ranks in the graph
    var max_rank: u16 = 0;
    for (0..node_count) |i| {
        g.nodes.items[i].rank = ranks[i];
        if (ranks[i] > max_rank) {
            max_rank = ranks[i];
        }
    }

    // Step 3: Insert virtual dummy nodes for edges spanning > 1 rank
    const orig_edges_len = g.edges.items.len;
    for (0..orig_edges_len) |e_idx| {
        const u = g.edges.items[e_idx].source;
        const v = g.edges.items[e_idx].target;
        const u_rank = g.nodes.items[u].rank;
        const v_rank = g.nodes.items[v].rank;

        if (v_rank > u_rank + 1) {
            const span = v_rank - u_rank;
            const orig_edge_id = g.edges.items[e_idx].id;
            const orig_label = g.edges.items[e_idx].label;

            var prev_node = u;
            var r: u16 = 1;
            while (r < span) : (r += 1) {
                const dummy_id = try g.addDummyNode(allocator, orig_edge_id);
                g.nodes.items[dummy_id].rank = u_rank + r;

                if (r == 1) {
                    // Update original edge to point to the first dummy node
                    g.edges.items[e_idx].target = dummy_id;
                    g.edges.items[e_idx].orig_edge = orig_edge_id;
                } else {
                    // Chain from previous dummy node to current dummy node
                    _ = try g.addEdge(allocator, prev_node, dummy_id, if (r == 2) orig_label else "");
                    g.edges.items[g.edges.items.len - 1].orig_edge = orig_edge_id;
                }
                prev_node = dummy_id;
            }

            // Final edge from last dummy node to target v
            _ = try g.addEdge(allocator, prev_node, v, if (span == 2) orig_label else "");
            g.edges.items[g.edges.items.len - 1].orig_edge = orig_edge_id;
        }
    }

    // Step 4: Group nodes into discrete layers
    const num_layers: usize = max_rank + 1;
    const layers = try allocator.alloc(std.ArrayList(graph_mod.NodeId), num_layers);
    errdefer {
        for (layers) |*layer| layer.deinit(allocator);
        allocator.free(layers);
    }
    for (0..num_layers) |l| {
        layers[l] = std.ArrayList(graph_mod.NodeId).empty;
    }

    for (g.nodes.items) |n| {
        try layers[n.rank].append(allocator, n.id);
    }

    // Set initial order index within each layer
    for (layers) |layer| {
        for (layer.items, 0..) |n_id, order_idx| {
            g.nodes.items[n_id].order = @intCast(order_idx);
        }
    }

    return .{
        .graph = g,
        .layers = layers,
        .num_layers = num_layers,
    };
}

test "sugiyama layering assigns ranks and inserts dummy nodes" {
    var g = graph_mod.DirectedGraph.init();
    defer g.deinit(std.testing.allocator);

    const a = try g.addNode(std.testing.allocator, "A");
    const b = try g.addNode(std.testing.allocator, "B");
    const c = try g.addNode(std.testing.allocator, "C");
    const d = try g.addNode(std.testing.allocator, "D");

    // A -> B -> C -> D
    _ = try g.addEdge(std.testing.allocator, a, b, "");
    _ = try g.addEdge(std.testing.allocator, b, c, "");
    _ = try g.addEdge(std.testing.allocator, c, d, "");

    // Long edge A -> D spanning from rank 0 to rank 3 (span = 3)
    _ = try g.addEdge(std.testing.allocator, a, d, "long-link");

    var layered = try assignRanksAndLayers(std.testing.allocator, &g);
    defer layered.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), layered.num_layers);

    // Verify ranks:
    // A: 0
    // B: 1
    // C: 2
    // D: 3
    try std.testing.expectEqual(@as(u16, 0), g.nodes.items[a].rank);
    try std.testing.expectEqual(@as(u16, 1), g.nodes.items[b].rank);
    try std.testing.expectEqual(@as(u16, 2), g.nodes.items[c].rank);
    try std.testing.expectEqual(@as(u16, 3), g.nodes.items[d].rank);

    // Span of A -> D is 3, so 2 dummy nodes should be inserted:
    // one in layer 1, one in layer 2.
    // Layer 0: [A] (1 node)
    // Layer 1: [B, dummy1] (2 nodes)
    // Layer 2: [C, dummy2] (2 nodes)
    // Layer 3: [D] (1 node)
    try std.testing.expectEqual(@as(usize, 1), layered.layers[0].items.len);
    try std.testing.expectEqual(@as(usize, 2), layered.layers[1].items.len);
    try std.testing.expectEqual(@as(usize, 2), layered.layers[2].items.len);
    try std.testing.expectEqual(@as(usize, 1), layered.layers[3].items.len);

    // Total nodes = 4 original + 2 dummy = 6 nodes
    try std.testing.expectEqual(@as(usize, 6), g.nodes.items.len);

    // Check all edges are proper (span == 1)
    for (g.edges.items) |e| {
        const u_rank = g.nodes.items[e.source].rank;
        const v_rank = g.nodes.items[e.target].rank;
        try std.testing.expectEqual(u_rank + 1, v_rank);
    }
}

test "sugiyama layering handles diamond and cyclic graphs" {
    var g = graph_mod.DirectedGraph.init();
    defer g.deinit(std.testing.allocator);

    const a = try g.addNode(std.testing.allocator, "A");
    const b = try g.addNode(std.testing.allocator, "B");
    const c = try g.addNode(std.testing.allocator, "C");
    const d = try g.addNode(std.testing.allocator, "D");

    // Diamond: A -> B, A -> C, B -> D, C -> D
    _ = try g.addEdge(std.testing.allocator, a, b, "");
    _ = try g.addEdge(std.testing.allocator, a, c, "");
    _ = try g.addEdge(std.testing.allocator, b, d, "");
    _ = try g.addEdge(std.testing.allocator, c, d, "");

    // Cycle back: D -> A
    _ = try g.addEdge(std.testing.allocator, d, a, "back-edge");

    try g.breakCycles(std.testing.allocator);

    var layered = try assignRanksAndLayers(std.testing.allocator, &g);
    defer layered.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), layered.num_layers);
    try std.testing.expectEqual(@as(u16, 0), g.nodes.items[a].rank);
    try std.testing.expectEqual(@as(u16, 1), g.nodes.items[b].rank);
    try std.testing.expectEqual(@as(u16, 1), g.nodes.items[c].rank);
    try std.testing.expectEqual(@as(u16, 2), g.nodes.items[d].rank);
}
