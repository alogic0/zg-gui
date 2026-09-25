const std = @import("std");
const gui = @import("zg_gui");

const Entry = gui.snapshot.Entry;

const Timer = struct {
    start_ns: u64,

    fn start() Timer {
        return .{ .start_ns = now() };
    }

    fn reset(self: *Timer) void {
        self.start_ns = now();
    }

    fn read(self: *const Timer) u64 {
        const cur = now();
        return if (cur >= self.start_ns) cur - self.start_ns else 0;
    }

    fn now() u64 {
        var ts: std.os.linux.timespec = undefined;
        _ = std.os.linux.clock_gettime(std.os.linux.CLOCK.MONOTONIC, &ts);
        return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
    }
};

fn runBenchmarkForCapacity(comptime item_count: usize, comptime props_per_item: usize, iterations: usize) !void {
    const total_entries = item_count * props_per_item;
    const S = gui.snapshot.Snapshot(total_entries);

    std.debug.print("\n======================================================\n", .{});
    std.debug.print(" Benchmark: {d} items x {d} properties = {d} entries\n", .{ item_count, props_per_item, total_entries });
    std.debug.print(" Entry size: {d} bytes | Snapshot total: {d} bytes ({d:.1} KB)\n", .{
        @sizeOf(Entry),
        @sizeOf(S),
        @as(f64, @floatFromInt(@sizeOf(S))) / 1024.0,
    });
    std.debug.print(" Bytes per entry (including hash index): {d:.2} bytes\n", .{
        @as(f64, @floatFromInt(@sizeOf(S))) / @as(f64, @floatFromInt(total_entries)),
    });
    std.debug.print("======================================================\n", .{});

    // 1. Measure Cold Capture
    var timer = Timer.start();
    var snap1 = S{};
    for (0..iterations) |_| {
        snap1 = S{};
        for (0..item_count) |i| {
            const node: u32 = @intCast(i + 1);
            _ = try snap1.changed(.{ .previous = null, .change = .{ .node = node, .property = "#text", .value = "Item Label Header" } });
            _ = try snap1.changed(.{ .previous = null, .change = .{ .node = node, .property = "class", .value = "metric-card active" } });
            _ = try snap1.changed(.{ .previous = null, .change = .{ .node = node, .property = "data-kind", .value = "job-summary" } });
            _ = try snap1.changed(.{ .previous = null, .change = .{ .node = node, .property = "data-key", .value = "key-abc-12345" } });
            _ = try snap1.changed(.{ .previous = null, .change = .{ .node = node, .property = "style", .value = "opacity: 1;" } });
        }
    }
    const cold_time = timer.read();
    const cold_per_iter_us = @as(f64, @floatFromInt(cold_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0;
    const cold_per_entry_ns = @as(f64, @floatFromInt(cold_time)) / @as(f64, @floatFromInt(iterations * total_entries));
    std.debug.print(" Cold Capture:     {d:8.2} us/iter | {d:6.2} ns/entry\n", .{ cold_per_iter_us, cold_per_entry_ns });

    // 2. Measure Unchanged Patch (100% matches)
    timer.reset();
    var snap2 = S{};
    var diff_count: usize = 0;
    for (0..iterations) |_| {
        snap2 = S{};
        for (0..item_count) |i| {
            const node: u32 = @intCast(i + 1);
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "#text", .value = "Item Label Header" } })) diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "class", .value = "metric-card active" } })) diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-kind", .value = "job-summary" } })) diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-key", .value = "key-abc-12345" } })) diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "style", .value = "opacity: 1;" } })) diff_count += 1;
        }
    }
    const unchanged_time = timer.read();
    const unchanged_per_iter_us = @as(f64, @floatFromInt(unchanged_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0;
    const unchanged_per_entry_ns = @as(f64, @floatFromInt(unchanged_time)) / @as(f64, @floatFromInt(iterations * total_entries));
    std.debug.print(" Unchanged (hits): {d:8.2} us/iter | {d:6.2} ns/entry (diffs={d})\n", .{ unchanged_per_iter_us, unchanged_per_entry_ns, diff_count });

    // 3. Measure Single Item Edit (middle item changed)
    const mid = item_count / 2;
    timer.reset();
    var single_diff_count: usize = 0;
    for (0..iterations) |_| {
        snap2 = S{};
        for (0..item_count) |i| {
            const node: u32 = @intCast(i + 1);
            const is_edited = (i == mid);
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "#text", .value = if (is_edited) "Updated Label!" else "Item Label Header" } })) single_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "class", .value = "metric-card active" } })) single_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-kind", .value = "job-summary" } })) single_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-key", .value = "key-abc-12345" } })) single_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "style", .value = "opacity: 1;" } })) single_diff_count += 1;
        }
    }
    const single_edit_time = timer.read();
    const single_per_iter_us = @as(f64, @floatFromInt(single_edit_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0;
    const single_per_entry_ns = @as(f64, @floatFromInt(single_edit_time)) / @as(f64, @floatFromInt(iterations * total_entries));
    std.debug.print(" Single Edit:      {d:8.2} us/iter | {d:6.2} ns/entry (diffs/iter={d})\n", .{ single_per_iter_us, single_per_entry_ns, single_diff_count / iterations });

    // 4. Measure Reverse Permutation (all node indices reversed)
    timer.reset();
    var rev_diff_count: usize = 0;
    for (0..iterations) |_| {
        snap2 = S{};
        for (0..item_count) |i| {
            const node: u32 = @intCast(item_count - i);
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "#text", .value = "Item Label Header" } })) rev_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "class", .value = "metric-card active" } })) rev_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-kind", .value = "job-summary" } })) rev_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-key", .value = "key-abc-12345" } })) rev_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "style", .value = "opacity: 1;" } })) rev_diff_count += 1;
        }
    }
    const rev_time = timer.read();
    const rev_per_iter_us = @as(f64, @floatFromInt(rev_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0;
    const rev_per_entry_ns = @as(f64, @floatFromInt(rev_time)) / @as(f64, @floatFromInt(iterations * total_entries));
    std.debug.print(" Reverse Order:    {d:8.2} us/iter | {d:6.2} ns/entry (diffs/iter={d})\n", .{ rev_per_iter_us, rev_per_entry_ns, rev_diff_count / iterations });

    // 5. Total Replacement (all properties changed)
    timer.reset();
    var replace_diff_count: usize = 0;
    for (0..iterations) |_| {
        snap2 = S{};
        for (0..item_count) |i| {
            const node: u32 = @intCast(i + 1);
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "#text", .value = "Totally Different Value" } })) replace_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "class", .value = "inactive-item" } })) replace_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-kind", .value = "archived-row" } })) replace_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "data-key", .value = "key-xyz-99999" } })) replace_diff_count += 1;
            if (try snap2.changed(.{ .previous = &snap1, .change = .{ .node = node, .property = "style", .value = "display: none;" } })) replace_diff_count += 1;
        }
    }
    const replace_time = timer.read();
    const replace_per_iter_us = @as(f64, @floatFromInt(replace_time)) / @as(f64, @floatFromInt(iterations)) / 1000.0;
    const replace_per_entry_ns = @as(f64, @floatFromInt(replace_time)) / @as(f64, @floatFromInt(iterations * total_entries));
    std.debug.print(" Replacement:      {d:8.2} us/iter | {d:6.2} ns/entry (diffs/iter={d})\n", .{ replace_per_iter_us, replace_per_entry_ns, replace_diff_count / iterations });
}

fn runMicrobenchmark(iterations: usize) !void {
    std.debug.print("\n======================================================\n", .{});
    std.debug.print(" Microbenchmark: Wyhash vs Direct String Comparison\n", .{});
    std.debug.print("======================================================\n", .{});

    const s16 = "metric-card-1234";
    const s32 = "018f3a5e-b24a-7182-9a3b-28f09e80";
    const s64 = "background-color: rgb(240, 242, 245); padding: 12px 16px; margin: 4px;";

    var timer = Timer.start();
    var hash_accum: u64 = 0;
    for (0..iterations) |_| {
        hash_accum +%= std.hash.Wyhash.hash(0, s16);
        hash_accum +%= std.hash.Wyhash.hash(1, s32);
        hash_accum +%= std.hash.Wyhash.hash(2, s64);
    }
    const hash_time = timer.read();
    std.mem.doNotOptimizeAway(hash_accum);

    timer.reset();
    var cmp_accum: usize = 0;
    for (0..iterations) |_| {
        if (std.mem.eql(u8, s16, "metric-card-1234")) cmp_accum += 1;
        if (std.mem.eql(u8, s32, "018f3a5e-b24a-7182-9a3b-28f09e80")) cmp_accum += 1;
        if (std.mem.eql(u8, s64, "background-color: rgb(240, 242, 245); padding: 12px 16px; margin: 4px;")) cmp_accum += 1;
    }
    const cmp_time = timer.read();
    std.mem.doNotOptimizeAway(cmp_accum);

    const total_ops = iterations * 3;
    const ns_per_hash = @as(f64, @floatFromInt(hash_time)) / @as(f64, @floatFromInt(total_ops));
    const ns_per_cmp = @as(f64, @floatFromInt(cmp_time)) / @as(f64, @floatFromInt(total_ops));

    std.debug.print(" Wyhash (64-bit scalar):     {d:6.2} ns/op\n", .{ns_per_hash});
    std.debug.print(" Direct string equality:    {d:6.2} ns/op\n", .{ns_per_cmp});
    std.debug.print(" Ratio: Wyhash is {d:.2}x relative to direct memory comparison\n", .{ns_per_hash / ns_per_cmp});
}

pub fn main() !void {
    std.debug.print("\n=== zg-gui Snapshot Performance & Exact Identity Benchmarks ===\n", .{});

    try runMicrobenchmark(2_000_000);

    // 500 items x 5 props = 2,500 entries (typical large dashboard list)
    try runBenchmarkForCapacity(500, 5, 200);

    // 1,000 items x 5 props = 5,000 entries (stress test list)
    try runBenchmarkForCapacity(1000, 5, 100);

    std.debug.print("\nBenchmark completed successfully.\n\n", .{});
}
