const std = @import("std");

/// Declarative window configuration for virtual scrolling.
pub const Window = struct {
    item_height: u32,
    overscan: u32 = 3,

    pub const Slice = struct {
        start_index: usize,
        end_index: usize,
        top_spacer: u32,
        bottom_spacer: u32,
        total_height: u32,

        pub fn count(self: Slice) usize {
            return self.end_index - self.start_index;
        }
    };

    /// Calculates a viewport slice given current scroll position, viewport height, and total items.
    /// Operates with zero heap allocations and ensures exact total height conservation.
    pub fn calculate(self: Window, input: struct { scroll_top: u32, viewport_height: u32, total_items: usize }) Slice {
        if (self.item_height == 0 or input.total_items == 0) {
            return .{
                .start_index = 0,
                .end_index = 0,
                .top_spacer = 0,
                .bottom_spacer = 0,
                .total_height = 0,
            };
        }

        const total_height = @as(u32, @intCast(@min(input.total_items * self.item_height, std.math.maxInt(u32))));
        const visible_start = input.scroll_top / self.item_height;
        const visible_count = (input.viewport_height + self.item_height - 1) / self.item_height;

        const start = if (visible_start > self.overscan) visible_start - self.overscan else 0;
        const clamped_start = @min(start, input.total_items);

        const raw_end = visible_start + visible_count + self.overscan;
        const end = @min(input.total_items, raw_end);
        const clamped_end = @max(clamped_start, end);

        const top_spacer = @as(u32, @intCast(clamped_start)) * self.item_height;
        const remaining = input.total_items - clamped_end;
        const bottom_spacer = @as(u32, @intCast(remaining)) * self.item_height;

        return .{
            .start_index = clamped_start,
            .end_index = clamped_end,
            .top_spacer = top_spacer,
            .bottom_spacer = bottom_spacer,
            .total_height = total_height,
        };
    }
};

test "Window slice conserves total scroll height and bounds slice indices" {
    const w = Window{ .item_height = 40, .overscan = 5 };

    // At top of 10,000 item list
    const top = w.calculate(.{ .scroll_top = 0, .viewport_height = 800, .total_items = 10000 });
    try std.testing.expectEqual(@as(usize, 0), top.start_index);
    try std.testing.expectEqual(@as(usize, 25), top.end_index);
    try std.testing.expectEqual(@as(u32, 0), top.top_spacer);
    try std.testing.expectEqual(@as(u32, (10000 - 25) * 40), top.bottom_spacer);
    try std.testing.expectEqual(@as(u32, 400000), top.total_height);
    try std.testing.expectEqual(top.total_height, top.top_spacer + @as(u32, @intCast(top.count())) * 40 + top.bottom_spacer);

    // Scrolled into middle: scrollTop = 2000
    const mid = w.calculate(.{ .scroll_top = 2000, .viewport_height = 800, .total_items = 10000 });
    // visible_start = 50, visible_count = 20
    // start = 50 - 5 = 45
    // end = 50 + 20 + 5 = 75
    try std.testing.expectEqual(@as(usize, 45), mid.start_index);
    try std.testing.expectEqual(@as(usize, 75), mid.end_index);
    try std.testing.expectEqual(@as(usize, 30), mid.count());
    try std.testing.expectEqual(@as(u32, 45 * 40), mid.top_spacer);
    try std.testing.expectEqual(@as(u32, (10000 - 75) * 40), mid.bottom_spacer);
    try std.testing.expectEqual(mid.total_height, mid.top_spacer + @as(u32, @intCast(mid.count())) * 40 + mid.bottom_spacer);

    // Scrolled near bottom
    const bottom = w.calculate(.{ .scroll_top = 399500, .viewport_height = 800, .total_items = 10000 });
    try std.testing.expect(bottom.end_index == 10000);
    try std.testing.expectEqual(@as(u32, 0), bottom.bottom_spacer);
    try std.testing.expectEqual(bottom.total_height, bottom.top_spacer + @as(u32, @intCast(bottom.count())) * 40 + bottom.bottom_spacer);

    // Empty list
    const empty = w.calculate(.{ .scroll_top = 0, .viewport_height = 800, .total_items = 0 });
    try std.testing.expectEqual(@as(usize, 0), empty.count());
    try std.testing.expectEqual(@as(u32, 0), empty.total_height);
}
