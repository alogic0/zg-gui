const std = @import("std");
const c = @import("charts.zig");
const expect = std.testing.expect;
fn close(a: f64, b: f64) !void {
    try std.testing.expectApproxEqAbs(a, b, @max(@abs(a), 1) * 1e-12);
}
fn unit() !c.Linear {
    return c.Linear.init(.{ .domain = .{ .start = 0, .end = 10 }, .range = .{ .start = 0, .end = 100 } });
}
test "linear endpoint inverse monotonicity reversed clamped and constant invariants" {
    for ([_]bool{ false, true }) |reverse| {
        const scale = try c.Linear.init(.{ .domain = .{ .start = -30, .end = 70 }, .range = if (reverse) .{ .start = 600, .end = 20 } else .{ .start = 20, .end = 600 } });
        try close(scale.range.start, try scale.map(-30));
        try close(scale.range.end, try scale.map(70));
        var last = try scale.map(-30);
        for (0..101) |i| {
            const value: f64 = @as(f64, @floatFromInt(i)) - 30;
            const mapped = try scale.map(value);
            try close(value, try scale.invert(mapped));
            try expect(if (reverse) mapped <= last else mapped >= last);
            last = mapped;
        }
    }
    const constant = try c.Linear.init(.{ .domain = .{ .start = 3, .end = 3 }, .range = .{ .start = -100, .end = 100 } });
    try close(0, try constant.map(3));
    try close(3, try constant.invert(999));
    const clamped = try c.Linear.init(.{ .domain = .{ .start = 10, .end = -10 }, .range = .{ .start = 0, .end = 1 }, .clamp = true });
    try close(0, try clamped.map(20));
    try close(-10, try clamped.invert(20));
    const flat = try c.Linear.init(.{ .domain = .{ .start = 0, .end = 1 }, .range = .{ .start = 5, .end = 5 } });
    try std.testing.expectError(error.NonInvertibleRange, flat.invert(5));
}
test "linear extreme finite domains avoid intermediate overflow and reject unrepresentable results" {
    const max = std.math.floatMax(f64);
    const scale = try c.Linear.init(.{ .domain = .{ .start = -max, .end = max }, .range = .{ .start = max, .end = -max } });
    try close(max, try scale.map(-max));
    try close(0, try scale.map(0));
    try close(max / 2, try scale.invert(-max / 2));
    const tiny = try c.Linear.init(.{ .domain = .{ .start = 0, .end = std.math.floatTrueMin(f64) }, .range = .{ .start = 0, .end = 1 } });
    try close(1, try tiny.map(std.math.floatTrueMin(f64)));
    try std.testing.expectError(error.Overflow, tiny.map(max));
    try std.testing.expectError(error.NonFinite, scale.map(std.math.nan(f64)));
    try std.testing.expectError(error.NonFinite, c.Linear.init(.{ .domain = .{ .start = 0, .end = std.math.inf(f64) }, .range = .{ .start = 0, .end = 1 } }));
}
test "bands stay disjoint inside range and reverse category order" {
    for ([_]bool{ false, true }) |reverse| {
        const band = try c.Band.init(.{ .count = 20, .range = if (reverse) .{ .start = 1000, .end = 0 } else .{ .start = 0, .end = 1000 }, .inner_padding = 0.2, .outer_padding = 0.3 });
        for (0..20) |i| {
            const span = try band.at(i);
            try expect(span.start >= 0 and span.end <= 1000 and span.width > 0);
            try close((span.start + span.end) / 2, span.center);
            if (i != 0) {
                const prior = try band.at(i - 1);
                try expect(if (reverse) span.end < prior.start else span.start > prior.end);
            }
        }
    }
    const empty = try c.Band.init(.{ .count = 0, .range = .{ .start = 0, .end = 1 } });
    try std.testing.expectError(error.IndexOutOfBounds, empty.at(0));
    try std.testing.expectError(error.InvalidPadding, c.Band.init(.{ .count = 1, .range = .{ .start = 0, .end = 1 }, .inner_padding = 2 }));
}
test "ticks remain finite ordered unique and inside signed constant tiny and extreme domains" {
    const max = std.math.floatMax(f64);
    const domains = [_]c.Interval{ .{ .start = -10, .end = 10 }, .{ .start = 8, .end = 0 }, .{ .start = 4, .end = 4 }, .{ .start = -max, .end = max }, .{ .start = 1e-310, .end = 9e-310 }, .{ .start = 0, .end = std.math.floatTrueMin(f64) }, .{ .start = 1e300, .end = 1.000000000000001e300 } };
    for (domains) |domain| for ([_]usize{ 1, 2, 6, 128 }) |target| {
        var memory: [c.max_ticks]f64 = undefined;
        const result = try c.ticks(.{ .domain = domain, .target_count = target, .output = &memory });
        try expect(result.values.len > 0 and result.values.len <= c.max_ticks);
        try expect(result.step > 0 and std.math.isFinite(result.step));
        for (result.values, 0..) |value, i| {
            try expect(std.math.isFinite(value) and value >= @min(domain.start, domain.end) and value <= @max(domain.start, domain.end));
            if (i != 0) try expect(value > result.values[i - 1]);
            var text: [384]u8 = undefined;
            try expect((try c.formatTick(.{ .value = value, .step = result.step, .buffer = &text })).len > 0);
        }
    };
    var output = [_]f64{123};
    try std.testing.expectError(error.CapacityExceeded, c.ticks(.{ .domain = .{ .start = -10, .end = 10 }, .output = &output }));
    try close(123, output[0]);
    var short = [_]u8{'!'};
    try std.testing.expectError(error.CapacityExceeded, c.formatTick(.{ .value = 1000, .step = 1, .buffer = &short }));
    try expect(short[0] == '!');
}
test "axes share scaled positions and orient marks labels and grids on all four sides" {
    const scale = try unit();
    for ([_]c.Axis.Orientation{ .top, .bottom, .left, .right }) |orientation| {
        const axis = try c.Axis.init(.{ .scale = scale, .orientation = orientation, .origin = 20, .grid_length = 50 });
        const tick = try axis.tick(5);
        try close(50, tick.position);
        const horizontal = orientation == .top or orientation == .bottom;
        try close(50, if (horizontal) tick.label.x else tick.label.y);
        const mark_end = if (horizontal) tick.mark.end.y else tick.mark.end.x;
        const grid_end = if (horizontal) tick.grid.end.y else tick.grid.end.x;
        try expect((mark_end - 20) * (grid_end - 20) < 0);
        try expect(tick.anchor == if (horizontal) c.Axis.Anchor.middle else if (orientation == .left) c.Axis.Anchor.end else c.Axis.Anchor.start);
    }
}
test "line gaps clipping singletons and transactional capacity preserve crossing geometry" {
    const scale = try c.Linear.init(.{ .domain = .{ .start = 0, .end = 10 }, .range = .{ .start = 0, .end = 10 } });
    const points = [_]?c.Point{ .{ .x = -5, .y = 5 }, .{ .x = 15, .y = 5 }, null, .{ .x = 3, .y = 2 }, .{ .x = 4, .y = 3 } };
    var buffer: [256]u8 = undefined;
    const path = try c.linePath(.{ .points = &points, .x_scale = scale, .y_scale = scale, .clip = .{ .x = 0, .y = 0, .width = 10, .height = 10 }, .buffer = &buffer });
    try std.testing.expectEqualStrings("M0,5L10,5M3,2L4,3", path);
    const singleton = [_]?c.Point{.{ .x = 3, .y = 2 }};
    try std.testing.expectEqualStrings("M3,2", try c.linePath(.{ .points = &singleton, .x_scale = scale, .y_scale = scale, .buffer = &buffer }));
    try std.testing.expectEqualStrings("", try c.linePath(.{ .points = &.{}, .x_scale = scale, .y_scale = scale, .buffer = &buffer }));
    var short = [_]u8{ '!', '!' };
    try std.testing.expectError(error.CapacityExceeded, c.linePath(.{ .points = &points, .x_scale = scale, .y_scale = scale, .buffer = &short }));
    try std.testing.expectEqualSlices(u8, "!!", &short);
    const bad = [_]?c.Point{ .{ .x = 1, .y = 1 }, .{ .x = std.math.nan(f64), .y = 2 } };
    try std.testing.expectError(error.NonFinite, c.linePath(.{ .points = &bad, .x_scale = scale, .y_scale = scale, .buffer = &short }));
    try std.testing.expectEqualSlices(u8, "!!", &short);
}
test "bars share zero baseline preserve signed values and caller keys with clipping and missing data" {
    const band = try c.Band.init(.{ .count = 4, .range = .{ .start = 0, .end = 400 } });
    const values = try c.Linear.init(.{ .domain = .{ .start = -10, .end = 10 }, .range = .{ .start = 200, .end = 0 } });
    const data = [_]c.BarDatum{ .{ .key = 42, .category = 0, .value = 5 }, .{ .key = 7, .category = 1, .value = -5 }, .{ .key = 11, .category = 2, .value = 0 }, .{ .key = 3, .category = 3, .value = null } };
    var output: [4]c.Bar = undefined;
    const bars = try c.bars(.{ .data = &data, .categories = band, .values = values, .output = &output });
    try expect(bars.len == 3 and bars[0].key == 42 and bars[1].key == 7);
    try close(100, bars[0].rect.y + bars[0].rect.height);
    try close(100, bars[1].rect.y);
    try close(bars[0].rect.height, bars[1].rect.height);
    try close(0, bars[2].rect.height);
    const reordered = [_]c.BarDatum{ data[1], data[0] };
    const again = try c.bars(.{ .data = &reordered, .categories = band, .values = values, .output = &output });
    try expect(again[0].key == 7 and again[1].key == 42);
    const copy = output;
    const invalid = [_]c.BarDatum{ data[0], data[0] };
    try std.testing.expectError(error.DuplicateKey, c.bars(.{ .data = &invalid, .categories = band, .values = values, .output = &output }));
    try std.testing.expectEqualDeep(copy, output);
    const clipped = try c.bars(.{ .data = &data, .categories = band, .values = values, .clip = .{ .x = 0, .y = 75, .width = 400, .height = 50 }, .output = &output });
    try close(25, clipped[0].rect.height);
    try close(25, clipped[1].rect.height);
}

test "constant fractional domains label their actual value and signed zero normalizes" {
    var ticks: [4]f64 = undefined;
    const result = try c.ticks(.{ .domain = .{ .start = 4.25, .end = 4.25 }, .output = &ticks });
    var text: [32]u8 = undefined;
    try std.testing.expectEqualStrings("4.25", try c.formatTick(.{ .value = result.values[0], .step = result.step, .buffer = &text }));
    try std.testing.expectEqualStrings("0", try c.formatTick(.{ .value = -0.0, .step = 1, .buffer = &text }));
}

test "bar invalid values and axis overflow do not publish partial caller storage" {
    const band = try c.Band.init(.{ .count = 2, .range = .{ .start = 0, .end = 100 } });
    const values = try unit();
    const sentinel = c.Bar{ .key = 123, .value = 456, .rect = .{ .x = 1, .y = 2, .width = 3, .height = 4 } };
    var output = [2]c.Bar{ sentinel, sentinel };
    const invalid = [_]c.BarDatum{ .{ .key = 1, .category = 0, .value = 4 }, .{ .key = 2, .category = 1, .value = std.math.inf(f64) } };
    try std.testing.expectError(error.NonFinite, c.bars(.{ .data = &invalid, .categories = band, .values = values, .output = &output }));
    try std.testing.expectEqualDeep(sentinel, output[0]);
    const horizontal = try c.bars(.{ .data = invalid[0..1], .categories = band, .values = values, .orientation = .horizontal, .output = &output });
    try close(0, horizontal[0].rect.x);
    try close(40, horizontal[0].rect.width);
    const axis = try c.Axis.init(.{ .scale = values, .orientation = .right, .origin = std.math.floatMax(f64), .tick_size = std.math.floatMax(f64) });
    try std.testing.expectError(error.Overflow, axis.tick(5));
}
