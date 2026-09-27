//! Native static file development and test preview server for zg-gui.
const std = @import("std");
const preview_listener = @import("preview_listener.zig");

pub const Options = struct {
    root: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;

    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();

    var host: []const u8 = "127.0.0.1";
    var port: u16 = 4180;
    var root: []const u8 = "zig-out/web";
    var managed = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--host")) {
            host = args.next() orelse return error.MissingHost;
        } else if (std.mem.eql(u8, arg, "--port")) {
            const p_str = args.next() orelse return error.MissingPort;
            port = try std.fmt.parseInt(u16, p_str, 10);
        } else if (std.mem.eql(u8, arg, "--root")) {
            root = args.next() orelse return error.MissingRoot;
        } else if (std.mem.eql(u8, arg, "--managed")) {
            managed = true;
        }
    }

    if (std.mem.eql(u8, host, "localhost")) host = "127.0.0.1";

    const cwd = try std.Io.Dir.cwd().realPathFileAlloc(io, ".", a);
    const abs_root = try std.fs.path.resolve(a, &.{ cwd, root });

    var listener = try preview_listener.listen(io, try std.Io.net.IpAddress.parse(host, port));
    defer listener.deinit(io);

    const actual_port = listener.socket.address.getPort();
    const options: Options = .{ .root = abs_root };

    if (managed) {
        var stdout = std.Io.File.stdout();
        const json = try std.json.Stringify.valueAlloc(a, .{
            .address = host,
            .port = actual_port,
        }, .{});
        try stdout.writeStreamingAll(io, json);
        try stdout.writeStreamingAll(io, "\n");

        var storage: [2]union(enum) { server: anyerror!void, parent: void } = undefined;
        var select: std.Io.Select(@typeInfo(@TypeOf(storage)).array.child) = .init(io, &storage);
        defer select.cancelDiscard();
        try select.concurrent(.server, serve, .{ io, &listener, options });
        try select.concurrent(.parent, parentClosed, .{io});
        switch (try select.await()) {
            .server => |result| try result,
            .parent => {},
        }
    } else {
        std.debug.print("zg-gui server running: http://{s}:{d}\n", .{ host, actual_port });
        try serve(io, &listener, options);
    }
}

fn parentClosed(io: std.Io) void {
    var buffer: [128]u8 = undefined;
    var reader = std.Io.File.stdin().reader(io, &buffer);
    while (true) _ = reader.interface.takeByte() catch return;
}

pub fn serve(io: std.Io, listener: *std.Io.net.Server, options: Options) !void {
    var group: std.Io.Group = .init;
    defer group.cancel(io);
    while (true) {
        const stream = try listener.accept(io);
        group.concurrent(io, connection, .{ io, stream, options }) catch |err| {
            stream.close(io);
            return err;
        };
    }
}

fn connection(io: std.Io, stream: std.Io.net.Stream, options: Options) void {
    defer stream.close(io);
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var read_buffer: [32768]u8 = undefined;
    var write_buffer: [16384]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);
    var writer = stream.writer(io, &write_buffer);

    var server = std.http.Server.init(&reader.interface, &writer.interface);
    var request = server.receiveHead() catch return;

    handle(a, io, &request, options) catch |err| {
        if (err != error.Canceled) {
            std.debug.print("Preview request failed: {s}\n", .{@errorName(err)});
        }
    };
}

fn handle(a: std.mem.Allocator, io: std.Io, request: *std.http.Server.Request, options: Options) !void {
    const target = request.head.target;
    if (!std.mem.startsWith(u8, target, "/") or std.mem.startsWith(u8, target, "//") or std.mem.indexOfAny(u8, target, "\r\n\\") != null) {
        return request.respond("Invalid target", .{ .status = .bad_request, .keep_alive = false });
    }

    if (request.head.method != .GET and request.head.method != .HEAD) {
        return request.respond("Method not allowed", .{ .status = .method_not_allowed, .keep_alive = false });
    }

    const query_pos = std.mem.indexOfScalar(u8, target, '?') orelse target.len;
    const raw_path = target[0..query_pos];
    const path = decodeUri(a, raw_path) catch return request.respond("Not found", .{ .status = .not_found, .keep_alive = false });

    var components = std.mem.splitAny(u8, path, "/\\");
    while (components.next()) |part| {
        if (std.mem.eql(u8, part, "..")) {
            return request.respond("Forbidden", .{ .status = .forbidden, .keep_alive = false });
        }
    }

    var relative = std.mem.trimStart(u8, path, "/\\");
    if (relative.len == 0) relative = "index.html";

    var file_path = try std.fs.path.join(a, &.{ options.root, relative });

    // If file not found in root, check fallback paths like stripping web/ or prepending web/
    var opened_file = std.Io.Dir.cwd().openFile(io, file_path, .{});
    if (opened_file == error.FileNotFound) {
        if (std.mem.startsWith(u8, relative, "web/") or std.mem.startsWith(u8, relative, "web\\")) {
            const stripped = relative[4..];
            const stripped_rel = if (stripped.len == 0) "index.html" else stripped;
            const stripped_path = try std.fs.path.join(a, &.{ options.root, stripped_rel });
            opened_file = std.Io.Dir.cwd().openFile(io, stripped_path, .{});
            if (opened_file != error.FileNotFound and opened_file != error.AccessDenied) {
                file_path = stripped_path;
            }
        }
    }
    if (opened_file == error.FileNotFound) {
        const alt_path = try std.fs.path.join(a, &.{ "web", relative });
        opened_file = std.Io.Dir.cwd().openFile(io, alt_path, .{});
        if (opened_file != error.FileNotFound and opened_file != error.AccessDenied) {
            file_path = alt_path;
        }
    }

    if (opened_file) |file| {
        defer file.close(io);
        const stat = try file.stat(io);
        if (stat.kind == .file) {
            var headers: [3]std.http.Header = .{
                .{ .name = "Cache-Control", .value = "no-store" },
                .{ .name = "Content-Type", .value = contentType(file_path) },
                .{ .name = "Access-Control-Allow-Origin", .value = "*" },
            };

            var body_buffer: [16384]u8 = undefined;
            var body = try request.respondStreaming(&body_buffer, .{
                .content_length = stat.size,
                .respond_options = .{ .keep_alive = false, .extra_headers = &headers },
            });

            if (request.head.method != .HEAD) {
                var buffer: [16384]u8 = undefined;
                var file_reader = file.reader(io, &buffer);
                try file_reader.interface.streamExact64(&body.writer, stat.size);
            }
            return body.end();
        }
    } else |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.NotDir => {},
        else => return err,
    }

    return request.respond("Not found", .{ .status = .not_found, .keep_alive = false });
}

fn contentType(path: []const u8) []const u8 {
    const ext = std.fs.path.extension(path);
    if (std.mem.eql(u8, ext, ".html")) return "text/html; charset=utf-8";
    if (std.mem.eql(u8, ext, ".js") or std.mem.eql(u8, ext, ".mjs")) return "text/javascript; charset=utf-8";
    if (std.mem.eql(u8, ext, ".css")) return "text/css; charset=utf-8";
    if (std.mem.eql(u8, ext, ".wasm")) return "application/wasm";
    if (std.mem.eql(u8, ext, ".svg")) return "image/svg+xml; charset=utf-8";
    if (std.mem.eql(u8, ext, ".png")) return "image/png";
    if (std.mem.eql(u8, ext, ".json")) return "application/json; charset=utf-8";
    if (std.mem.eql(u8, ext, ".txt")) return "text/plain; charset=utf-8";
    return "application/octet-stream";
}

fn decodeUri(a: std.mem.Allocator, input: []const u8) ![]const u8 {
    const out = try a.alloc(u8, input.len);
    errdefer a.free(out);
    var n: usize = 0;
    var i: usize = 0;
    while (i < input.len) : (i += 1) {
        out[n] = if (input[i] == '%') blk: {
            if (i + 2 >= input.len) return error.InvalidEscape;
            const value = std.fmt.parseInt(u8, input[i + 1 ..][0..2], 16) catch return error.InvalidEscape;
            i += 2;
            break :blk value;
        } else input[i];
        n += 1;
    }
    if (!std.unicode.utf8ValidateSlice(out[0..n])) return error.InvalidEscape;
    return out[0..n];
}
