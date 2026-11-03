//! Verify the complete reviewed snapshot; this tool never refreshes sources.
const std = @import("std");
const Manifest = struct { schema: u32, source: []const u8, revision: []const u8, version: []const u8, license: []const u8, files: std.json.ArrayHashMap([]const u8) };
pub const VerifyOptions = struct { allocator: std.mem.Allocator, io: std.Io, root: []const u8, lock: []const u8 };
pub fn verify(input: VerifyOptions) !void {
    const a = input.allocator;
    const io = input.io;
    const content = try std.Io.Dir.cwd().readFileAlloc(io, input.lock, a, .limited(64 * 1024));
    defer a.free(content);
    const manifest = try std.json.parseFromSlice(Manifest, a, content, .{});
    defer manifest.deinit();
    const m = manifest.value;
    if (m.schema != 1 or !std.mem.eql(u8, m.source, "zig-mermaid-viewer") or m.revision.len != 40 or m.files.map.count() == 0 or !m.files.map.contains(m.license)) return error.InvalidProvenance;
    for (m.revision) |c| if (!std.ascii.isHex(c)) return error.InvalidProvenance;
    var root = try std.Io.Dir.cwd().openDir(io, input.root, .{ .iterate = true });
    defer root.close(io);
    var walk = try root.walk(a);
    defer walk.deinit();
    var count: usize = 0;
    while (try walk.next(io)) |entry| {
        if (entry.kind == .directory) continue;
        if (entry.kind != .file) return error.UnexpectedSnapshotFile;
        const expected = m.files.map.get(entry.path) orelse return error.UnexpectedSnapshotFile;
        const bytes = try root.readFileAlloc(io, entry.path, a, .limited(4 * 1024 * 1024));
        defer a.free(bytes);
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);
        if (!std.mem.eql(u8, expected, &hex)) return error.SnapshotHashMismatch;
        count += 1;
    }
    if (count != m.files.map.count()) return error.MissingSnapshotFile;
    const zon = try root.readFileAlloc(io, "build.zig.zon", a, .limited(16384));
    defer a.free(zon);
    const version = try std.fmt.allocPrint(a, ".version = \"{s}\"", .{m.version});
    defer a.free(version);
    if (std.mem.indexOf(u8, zon, version) == null) return error.InvalidProvenance;
}

pub fn main(init: std.process.Init) !void {
    try verify(.{ .allocator = init.arena.allocator(), .io = init.io, .root = "vendor/diagram_engine", .lock = "vendor/diagram_engine.lock.json" });
    std.debug.print("Verified pinned diagram engine source\n", .{});
}

test "snapshot verifier rejects changed, missing and unexpected files" {
    const io = std.testing.io;
    const a = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const root = try tmp.dir.realPathFileAlloc(io, ".", a);
    defer a.free(root);
    const lock = try std.fs.path.join(a, &.{ root, "lock.json" });
    defer a.free(lock);
    const source = try std.fs.path.join(a, &.{ root, "source" });
    defer a.free(source);
    try tmp.dir.createDir(io, "source", .default_dir);
    const zon = ".{ .version = \"0.9.0\" }";
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(zon, &digest, .{});
    const hash = std.fmt.bytesToHex(digest, .lower);
    const manifest = try std.fmt.allocPrint(a, "{{\"schema\":1,\"source\":\"zig-mermaid-viewer\",\"revision\":\"0000000000000000000000000000000000000000\",\"version\":\"0.9.0\",\"license\":\"LICENSE\",\"files\":{{\"build.zig.zon\":\"{s}\",\"LICENSE\":\"{s}\"}}}}", .{ hash, hash });
    defer a.free(manifest);
    try tmp.dir.writeFile(io, .{ .sub_path = "lock.json", .data = manifest });
    try tmp.dir.writeFile(io, .{ .sub_path = "source/build.zig.zon", .data = zon });
    try tmp.dir.writeFile(io, .{ .sub_path = "source/LICENSE", .data = zon });
    const input = VerifyOptions{ .allocator = a, .io = io, .root = source, .lock = lock };
    try verify(input);
    try tmp.dir.writeFile(io, .{ .sub_path = "source/LICENSE", .data = "modified" });
    try std.testing.expectError(error.SnapshotHashMismatch, verify(input));
    try tmp.dir.deleteFile(io, "source/LICENSE");
    try std.testing.expectError(error.MissingSnapshotFile, verify(input));
    try tmp.dir.writeFile(io, .{ .sub_path = "source/LICENSE", .data = zon });
    try tmp.dir.writeFile(io, .{ .sub_path = "source/unexpected", .data = "extra" });
    try std.testing.expectError(error.UnexpectedSnapshotFile, verify(input));
    try tmp.dir.deleteFile(io, "source/unexpected");
    try tmp.dir.symLink(io, "build.zig.zon", "source/link", .{});
    try std.testing.expectError(error.UnexpectedSnapshotFile, verify(input));
}
