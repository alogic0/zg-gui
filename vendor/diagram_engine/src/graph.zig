//! Graph data structures and foundational algorithms.
//! Uses dense index arrays for cache-locality and bounded memory.
const std = @import("std");

pub const NodeId = u32;
pub const EdgeId = u32;

pub const Node = struct {
    id: NodeId,
    name: []const u8,
    width: f32 = 0,
    height: f32 = 0,
    rank: u16 = 0,
    order: u16 = 0,
    x: f32 = 0,
    y: f32 = 0,
    is_dummy: bool = false,
    orig_edge: ?EdgeId = null,
};

pub const Edge = struct {
    id: EdgeId,
    source: NodeId,
    target: NodeId,
    label: []const u8 = "",
    weight: u16 = 1,
    min_len: u16 = 1,
    reversed: bool = false,
    orig_edge: ?EdgeId = null,
};

pub const DirectedGraph = struct {
    nodes: std.ArrayList(Node),
    edges: std.ArrayList(Edge),

    pub fn init() DirectedGraph {
        return .{
            .nodes = std.ArrayList(Node).empty,
            .edges = std.ArrayList(Edge).empty,
        };
    }

    pub fn deinit(self: *DirectedGraph, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
        self.edges.deinit(allocator);
    }

    pub fn addNode(self: *DirectedGraph, allocator: std.mem.Allocator, name: []const u8) !NodeId {
        if (self.findNodeByName(name)) |existing| {
            return existing;
        }
        const id: NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(allocator, .{
            .id = id,
            .name = name,
        });
        return id;
    }

    pub fn addDummyNode(self: *DirectedGraph, allocator: std.mem.Allocator, orig_edge: ?EdgeId) !NodeId {
        const id: NodeId = @intCast(self.nodes.items.len);
        try self.nodes.append(allocator, .{
            .id = id,
            .name = "",
            .is_dummy = true,
            .orig_edge = orig_edge,
        });
        return id;
    }

    pub fn findNodeByName(self: DirectedGraph, name: []const u8) ?NodeId {
        for (self.nodes.items, 0..) |n, i| {
            if (!n.is_dummy and std.mem.eql(u8, n.name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }

    pub fn addEdge(
        self: *DirectedGraph,
        allocator: std.mem.Allocator,
        source: NodeId,
        target: NodeId,
        label: []const u8,
    ) !EdgeId {
        const id: EdgeId = @intCast(self.edges.items.len);
        try self.edges.append(allocator, .{
            .id = id,
            .source = source,
            .target = target,
            .label = label,
        });
        return id;
    }

    /// Eades, Lin, Smyth (1993) greedy feedback arc set.
    /// Reverses back-edges to guarantee a Directed Acyclic Graph (DAG).
    pub fn breakCycles(self: *DirectedGraph, allocator: std.mem.Allocator) !void {
        const n = self.nodes.items.len;
        if (n <= 1) return;

        var in_deg = try allocator.alloc(i32, n);
        defer allocator.free(in_deg);
        @memset(in_deg, 0);

        var out_deg = try allocator.alloc(i32, n);
        defer allocator.free(out_deg);
        @memset(out_deg, 0);

        for (self.edges.items) |e| {
            out_deg[e.source] += 1;
            in_deg[e.target] += 1;
        }

        var active = try allocator.alloc(bool, n);
        defer allocator.free(active);
        @memset(active, true);

        // s1 grows from left, s2 from right
        var order = try allocator.alloc(NodeId, n);
        defer allocator.free(order);
        var s1_idx: usize = 0;
        var s2_idx: usize = n;
        var active_count = n;

        while (active_count > 0) {
            // Sinks: out_deg == 0
            var found_sink = true;
            while (found_sink) {
                found_sink = false;
                var u: usize = 0;
                while (u < n) : (u += 1) {
                    if (active[u] and out_deg[u] == 0) {
                        s2_idx -= 1;
                        order[s2_idx] = @intCast(u);
                        active[u] = false;
                        active_count -= 1;
                        found_sink = true;
                        // Decrement out_deg of in-neighbors
                        for (self.edges.items) |e| {
                            if (e.target == u and active[e.source]) {
                                out_deg[e.source] -= 1;
                            }
                        }
                    }
                }
            }

            // Sources: in_deg == 0
            var found_source = true;
            while (found_source) {
                found_source = false;
                var u: usize = 0;
                while (u < n) : (u += 1) {
                    if (active[u] and in_deg[u] == 0) {
                        order[s1_idx] = @intCast(u);
                        s1_idx += 1;
                        active[u] = false;
                        active_count -= 1;
                        found_source = true;
                        // Decrement in_deg of out-neighbors
                        for (self.edges.items) |e| {
                            if (e.source == u and active[e.target]) {
                                in_deg[e.target] -= 1;
                            }
                        }
                    }
                }
            }

            if (active_count == 0) break;

            // Pick vertex with maximum (out_deg - in_deg)
            var max_val: i32 = std.math.minInt(i32);
            var best_u: usize = 0;
            var u: usize = 0;
            while (u < n) : (u += 1) {
                if (active[u]) {
                    const diff = out_deg[u] - in_deg[u];
                    if (diff > max_val) {
                        max_val = diff;
                        best_u = u;
                    }
                }
            }

            order[s1_idx] = @intCast(best_u);
            s1_idx += 1;
            active[best_u] = false;
            active_count -= 1;
            for (self.edges.items) |e| {
                if (e.source == best_u and active[e.target]) {
                    in_deg[e.target] -= 1;
                }
                if (e.target == best_u and active[e.source]) {
                    out_deg[e.source] -= 1;
                }
            }
        }

        // Map node ID to position in total order
        var pos = try allocator.alloc(usize, n);
        defer allocator.free(pos);
        for (order, 0..) |u, idx| {
            pos[u] = idx;
        }

        // Any edge pointing backwards in total order is reversed
        for (self.edges.items) |*e| {
            if (pos[e.source] > pos[e.target]) {
                const tmp = e.source;
                e.source = e.target;
                e.target = tmp;
                e.reversed = true;
            }
        }
    }

    /// Computes topological sort of the graph nodes. Assumes the graph is a DAG.
    pub fn topologicalSort(self: DirectedGraph, allocator: std.mem.Allocator) ![]NodeId {
        const n = self.nodes.items.len;
        var in_deg = try allocator.alloc(u32, n);
        defer allocator.free(in_deg);
        @memset(in_deg, 0);

        for (self.edges.items) |e| {
            in_deg[e.target] += 1;
        }

        var queue = try allocator.alloc(NodeId, n);
        defer allocator.free(queue);
        var q_head: usize = 0;
        var q_tail: usize = 0;

        for (in_deg, 0..) |deg, i| {
            if (deg == 0) {
                queue[q_tail] = @intCast(i);
                q_tail += 1;
            }
        }

        var result = try allocator.alloc(NodeId, n);
        errdefer allocator.free(result);
        var count: usize = 0;

        while (q_head < q_tail) {
            const u = queue[q_head];
            q_head += 1;
            result[count] = u;
            count += 1;

            for (self.edges.items) |e| {
                if (e.source == u) {
                    in_deg[e.target] -= 1;
                    if (in_deg[e.target] == 0) {
                        queue[q_tail] = e.target;
                        q_tail += 1;
                    }
                }
            }
        }

        if (count < n) {
            return error.GraphHasCycles;
        }
        return result;
    }
};

test "directed graph construction and topological sort" {
    var g = DirectedGraph.init();
    defer g.deinit(std.testing.allocator);

    const a = try g.addNode(std.testing.allocator, "A");
    const b = try g.addNode(std.testing.allocator, "B");
    const c = try g.addNode(std.testing.allocator, "C");

    _ = try g.addEdge(std.testing.allocator, a, b, "");
    _ = try g.addEdge(std.testing.allocator, b, c, "");

    const order = try g.topologicalSort(std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 3), order.len);
    try std.testing.expectEqual(a, order[0]);
    try std.testing.expectEqual(b, order[1]);
    try std.testing.expectEqual(c, order[2]);
}

test "greedy feedback arc set breaks cycle" {
    var g = DirectedGraph.init();
    defer g.deinit(std.testing.allocator);

    const a = try g.addNode(std.testing.allocator, "A");
    const b = try g.addNode(std.testing.allocator, "B");
    const c = try g.addNode(std.testing.allocator, "C");

    // Cycle A -> B -> C -> A
    _ = try g.addEdge(std.testing.allocator, a, b, "");
    _ = try g.addEdge(std.testing.allocator, b, c, "");
    _ = try g.addEdge(std.testing.allocator, c, a, "");

    // Initially topological sort fails because of cycle
    try std.testing.expectError(error.GraphHasCycles, g.topologicalSort(std.testing.allocator));

    // Break cycles
    try g.breakCycles(std.testing.allocator);

    // Now topological sort must succeed
    const order = try g.topologicalSort(std.testing.allocator);
    defer std.testing.allocator.free(order);

    try std.testing.expectEqual(@as(usize, 3), order.len);

    // Exactly one edge should be reversed
    var reversed_count: usize = 0;
    for (g.edges.items) |e| {
        if (e.reversed) reversed_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), reversed_count);
}
