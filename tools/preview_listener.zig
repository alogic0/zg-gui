//! Linux std.Io reuse_address enables REUSEPORT too. Bind with only
//! REUSEADDR so a preview can restart promptly without sharing an active port.
const std = @import("std");

pub fn listen(io: std.Io, address: std.Io.net.IpAddress) !std.Io.net.Server {
    if (@import("builtin").os.tag != .linux) return address.listen(io, .{});
    const os = std.os.linux;
    const raw = os.socket(if (address == .ip4) os.AF.INET else os.AF.INET6, os.SOCK.STREAM | os.SOCK.CLOEXEC, os.IPPROTO.TCP);
    try check(raw);
    const fd: std.posix.fd_t = @intCast(raw);
    errdefer _ = os.close(fd);
    const enabled: c_int = 1;
    try check(os.setsockopt(fd, os.SOL.SOCKET, os.SO.REUSEADDR, std.mem.asBytes(&enabled).ptr, @sizeOf(c_int)));
    var storage: os.sockaddr.storage = undefined;
    var length: os.socklen_t = undefined;
    switch (address) {
        .ip4 => |ip| {
            const value: *os.sockaddr.in = @ptrCast(&storage);
            value.* = .{ .port = std.mem.nativeToBig(u16, ip.port), .addr = @bitCast(ip.bytes) };
            length = @sizeOf(os.sockaddr.in);
        },
        .ip6 => |ip| {
            const value: *os.sockaddr.in6 = @ptrCast(&storage);
            value.* = .{ .port = std.mem.nativeToBig(u16, ip.port), .addr = ip.bytes, .flowinfo = ip.flow, .scope_id = ip.interface.index };
            length = @sizeOf(os.sockaddr.in6);
        },
    }
    try check(os.bind(fd, @ptrCast(&storage), length));
    try check(os.listen(fd, std.Io.net.default_kernel_backlog));
    try check(os.getsockname(fd, @ptrCast(&storage), &length));
    var actual = address;
    switch (actual) {
        .ip4 => |*ip| {
            const value: *os.sockaddr.in = @ptrCast(&storage);
            ip.port = std.mem.bigToNative(u16, value.port);
        },
        .ip6 => |*ip| {
            const value: *os.sockaddr.in6 = @ptrCast(&storage);
            ip.port = std.mem.bigToNative(u16, value.port);
        },
    }
    return .{ .socket = .{ .handle = fd, .address = actual }, .options = {} };
}

fn check(result: usize) !void {
    return switch (std.posix.errno(result)) {
        .SUCCESS => {},
        .ADDRINUSE => error.AddressInUse,
        .ACCES => error.AccessDenied,
        else => error.ListenFailed,
    };
}
