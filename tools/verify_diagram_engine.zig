//! Reject unlisted files and symbolic links before checking the Zig package hash.
const std = @import("std");

fn checkFiles(allocator: std.mem.Allocator, io: std.Io, root: std.Io.Dir) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const source = try root.readFileAllocOptions(io, "build.zig.zon", arena.allocator(), .limited(64 * 1024), .of(u8), 0);
    var diagnostics: std.zon.parse.Diagnostics = undefined;
    const manifest = try std.zon.parse.fromSlice(struct { paths: []const []const u8 }, .{
        .gpa = allocator,
        .arena = arena.allocator(),
        .source = source,
        .diagnostics = &diagnostics,
        .ignore_unknown_fields = true,
    });
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        if (entry.kind == .directory) continue;
        if (entry.kind != .file) return error.UnexpectedPackageFile;
        const path = if (std.fs.path.sep == '/') entry.path else blk: {
            const normalized = try arena.allocator().dupe(u8, entry.path);
            std.mem.replaceScalar(u8, normalized, std.fs.path.sep, '/');
            break :blk normalized;
        };
        for (manifest.paths) |allowed| {
            if (allowed.len == 0) break;
            const suffix = std.mem.cutPrefix(u8, path, allowed) orelse continue;
            if (suffix.len == 0 or suffix[0] == '/') break;
        } else return error.UnexpectedPackageFile;
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 2) return error.ExpectedPackageDirectory;
    var root = try std.Io.Dir.cwd().openDir(init.io, args[1], .{ .iterate = true });
    defer root.close(init.io);
    try checkFiles(init.gpa, init.io, root);
}

test "package inspection rejects unlisted files and symlinks" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.writeFile(io, .{ .sub_path = "build.zig.zon", .data = ".{ .paths = .{ \"build.zig.zon\", \"src\" } }" });
    try tmp.dir.createDir(io, "src", .default_dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "src/example.zig", .data = "" });
    try checkFiles(std.testing.allocator, io, tmp.dir);
    try tmp.dir.writeFile(io, .{ .sub_path = "src-extra", .data = "" });
    try std.testing.expectError(error.UnexpectedPackageFile, checkFiles(std.testing.allocator, io, tmp.dir));
    try tmp.dir.deleteFile(io, "src-extra");
    try tmp.dir.symLink(io, "example.zig", "src/link", .{});
    try std.testing.expectError(error.UnexpectedPackageFile, checkFiles(std.testing.allocator, io, tmp.dir));
}
