const std = @import("std");
const Harness = @import("../browser_harness.zig").Harness;

test "text files: bounded UTF-8 selection download cancellation and cleanup" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/file-host.js");
    try guard.evalCheck(@embedFile("file_host_checks.js"));
}
