const std = @import("std");
const Harness = @import("../browser_harness.zig").Harness;

test "browser math: finite output ownership rejection recovery and completed patch hooks" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/math-host.js");
    try guard.evalCheck(@embedFile("math_checks.js"));
}
