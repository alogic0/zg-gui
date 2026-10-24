//! Native Chromium browser unit test suite for zg-gui using Chrome DevTools Protocol (CDP).
//! Native headless testing of DOM host, WASM demo, and workspace components.
const std = @import("std");
const cdp = @import("cdp");
const harness = @import("browser_harness.zig");

pub const dom_tests = @import("browser/dom_tests.zig");
pub const worker_tests = @import("browser/worker_tests.zig");
pub const workspace_tests = @import("browser/workspace_tests.zig");

test {
    std.testing.refAllDecls(@This());
}

test "browser unit: headless chrome launches and handles target lifecycle" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var guard = try harness.Harness.getSession(alloc, io);
    defer guard.deinit();

    try guard.session.setContent(
        \\<main id="app">
        \\  <h1 id="greeting">Hello CDP</h1>
        \\  <button id="action" onclick="document.querySelector('#greeting').textContent='Clicked'">Click Me</button>
        \\</main>
    );

    try std.testing.expect(try guard.session.isVisible("#greeting"));
    try std.testing.expect(try guard.session.isVisible("#action"));

    const text1 = try guard.session.getText("#greeting");
    defer if (text1) |t| alloc.free(t);
    try std.testing.expect(text1 != null);
    try std.testing.expectEqualStrings("Hello CDP", text1.?);

    try guard.session.click("#action");

    const text2 = try guard.session.getText("#greeting");
    defer if (text2) |t| alloc.free(t);
    try std.testing.expect(text2 != null);
    try std.testing.expectEqualStrings("Clicked", text2.?);

    const screenshot = try guard.session.captureScreenshot();
    defer alloc.free(screenshot);
    try std.testing.expect(screenshot.len > 8);
    try std.testing.expectEqualStrings("\x89PNG\r\n\x1a\n", screenshot[0..8]);
}

test "browser unit: harness cleanup" {
    harness.Harness.deinit();
}
