const std = @import("std");
const Harness = @import("../browser_harness.zig").Harness;

test "shared startup: declarative WASM retained identity and independent roots" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/startup.html");
    try guard.evalCheck(@embedFile("startup_real_checks.js"));
}

test "shared startup: bounded manifest admission optional hosts and failure cleanup" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/startup.js");
    try guard.evalCheck(@embedFile("startup_failure_checks.js"));
}
