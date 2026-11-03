//! One test root for zg-gui native tools.
const std = @import("std");

test {
    _ = @import("cdp");
    _ = @import("lib/cdp_journey_test.zig");
    _ = @import("preview_listener.zig");
    _ = @import("serve.zig");
    _ = @import("verify_diagram_engine.zig");
}

test "std.json surrogate pair unescaping" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"value\":\"Studio \\ud83e\\udded <test>\"}", .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Studio 🧭 <test>", parsed.value.object.get("value").?.string);
}
