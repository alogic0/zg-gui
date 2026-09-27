//! Reusable browser test harness for native CDP testing.
//! Starts a headless Chromium instance and a managed preview server on demand,
//! and provides isolated tabs for each test case.
const std = @import("std");
const cdp = @import("lib/cdp.zig");

pub const Harness = struct {
    var browser: ?cdp.BrowserInstance = null;
    var server: ?std.process.Child = null;
    var client: ?cdp.CdpClient = null;
    var server_port: u16 = 0;
    const cdp_port: u16 = 9285;

    pub fn getSession(alloc: std.mem.Allocator, io: std.Io) !SessionGuard {
        if (browser == null) {
            browser = try cdp.launchHeadless(io, alloc, cdp_port);
            const serve_child = try std.process.spawn(io, .{
                .argv = &.{
                    "zig-out/bin/serve",
                    "--port",
                    "0",
                    "--managed",
                    "--root",
                    "zig-out/web",
                },
                .stdin = .pipe,
                .stdout = .pipe,
                .stderr = .ignore,
            });
            var stdout_pipe = serve_child.stdout.?;
            var rb: [1024]u8 = undefined;
            var r = stdout_pipe.reader(io, &rb);
            const line = try r.interface.takeDelimiterInclusive('\n');
            const parsed = try std.json.parseFromSlice(std.json.Value, alloc, std.mem.trim(u8, line, "\r\n "), .{});
            defer parsed.deinit();
            server_port = @as(u16, @intCast(parsed.value.object.get("port").?.integer));
            server = serve_child;
            client = cdp.CdpClient.init(alloc, io, cdp_port);
        }

        const target = try client.?.newTarget("about:blank");
        const session = try client.?.connectWs(target.web_socket_debugger_url);
        return SessionGuard{
            .session = session,
            .target = target,
            .client = client.?,
            .server_port = server_port,
            .alloc = alloc,
            .io = io,
        };
    }

    pub fn deinit() void {
        if (server) |*s| {
            s.kill(std.testing.io);
            server = null;
        }
        if (browser) |*b| {
            b.kill();
            browser = null;
        }
    }
};

pub const SessionGuard = struct {
    session: cdp.WsSession,
    target: cdp.Target,
    client: cdp.CdpClient,
    server_port: u16,
    alloc: std.mem.Allocator,
    io: std.Io,

    pub fn deinit(self: *SessionGuard) void {
        self.session.close();
        self.client.closeTarget(self.target.id) catch {};
        self.target.deinit(self.alloc);
    }

    pub fn goto(self: *SessionGuard, path: []const u8) !void {
        const url = try std.fmt.allocPrint(self.alloc, "http://127.0.0.1:{d}{s}", .{ self.server_port, path });
        defer self.alloc.free(url);
        try self.session.goto(url);
    }

    /// Evaluates an async expression in the browser, providing a lightweight assert library.
    /// If an assertion fails or an error is thrown, returns error.BrowserAssertionFailed.
    pub fn evalCheck(self: *SessionGuard, script: []const u8) !void {
        const is_expr = std.mem.indexOf(u8, script, "\n") == null and
            std.mem.indexOf(u8, script, ";") == null and
            std.mem.indexOf(u8, script, "return") == null and
            std.mem.indexOf(u8, script, "const ") == null and
            std.mem.indexOf(u8, script, "let ") == null;

        const body = if (is_expr)
            try std.fmt.allocPrint(self.alloc, "return await ({s});", .{script})
        else
            try self.alloc.dupe(u8, script);
        defer self.alloc.free(body);

        const full_script = try std.fmt.allocPrint(self.alloc,
            \\(async () => {{
            \\  const assert = {{
            \\    equal: (a, b, msg) => {{ if (a !== b) throw new Error((msg ? msg + ': ' : '') + 'Expected ' + JSON.stringify(a) + ' === ' + JSON.stringify(b)); }},
            \\    notEqual: (a, b, msg) => {{ if (a === b) throw new Error((msg ? msg + ': ' : '') + 'Expected ' + JSON.stringify(a) + ' !== ' + JSON.stringify(b)); }},
            \\    ok: (v, msg) => {{ if (!v) throw new Error((msg ? msg + ': ' : '') + 'Expected truthy, got ' + JSON.stringify(v)); }},
            \\    deepEqual: (a, b, msg) => {{
            \\      const sa = JSON.stringify(a), sb = JSON.stringify(b);
            \\      if (sa !== sb) throw new Error((msg ? msg + ': ' : '') + 'Deep equality failed: ' + sa + ' !== ' + sb);
            \\    }},
            \\    match: (str, regex, msg) => {{ if (!regex.test(str)) throw new Error((msg ? msg + ': ' : '') + 'Expected ' + str + ' to match ' + regex); }},
            \\  }};
            \\  {s}
            \\}})()
        , .{body});
        defer self.alloc.free(full_script);

        const reply = try self.session.evaluate(full_script);
        defer self.alloc.free(reply);

        if (std.mem.indexOf(u8, reply, "\"exceptionDetails\"") != null) {
            std.debug.print("Browser assertion exception:\n{s}\n", .{reply});
            return error.BrowserAssertionFailed;
        }
        if (std.mem.indexOf(u8, reply, "\"value\":false") != null) {
            std.debug.print("Browser assertion returned false:\n{s}\n", .{reply});
            return error.BrowserAssertionFailed;
        }
    }
};

test "browser harness: launches and runs simple evaluation" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    var guard = try Harness.getSession(alloc, io);
    defer guard.deinit();

    try guard.goto("/dom.js");
    try guard.evalCheck("1 + 1 === 2");
}
