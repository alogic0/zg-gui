const std = @import("std");
const Harness = @import("../browser_harness.zig").Harness;

test "browser requests: native modality focus callback ownership and runtime events" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/browser-host.js");
    try guard.evalCheck(@embedFile("browser_requests_checks.js"));
}
