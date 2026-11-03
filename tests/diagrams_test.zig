const std = @import("std");
const gui = @import("zg_gui");
const diagrams = @import("zg_diagrams");
const engine = diagrams.engine;
const View = diagrams.Diagram(64, 128);
const P = gui.Projection(View.snapshot_capacity);
const ns = gui.namespace.Range{ .first = 100, .count = View.node_count };

test "diagram labels and geometry patch existing nodes without replacing SVG" {
    var a = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n A[One] --> B[Two]" });
    defer a.deinit();
    var b = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph LR\n B[Updated <&>]\n A[One]\n A --> B" });
    defer b.deinit();
    var view = View{};
    var before = P.Snapshot{};
    var after = P.Snapshot{};
    var bytes: [32768]u8 = undefined;
    var patch_bytes: [32768]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &patch_bytes };
    var patches = gui.patch.Writer{ .output = &output };
    var p = P{ .html = &html, .next = &before };
    try view.project(&p, .{ .scene = &a, .namespace = ns, .description = "A simple graph" });
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "url(#zg-diagram-100-arrow)") != null);
    html.len = 0;
    p = .{ .html = &html, .next = &after, .previous = &before, .patches = &patches, .writing = false };
    try view.project(&p, .{ .scene = &b, .namespace = ns, .description = "A simple graph" });
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "T\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "Updated <&>") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "\td\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "H\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "J\t") == null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "D\t") == null);
}

test "diagram insertion and removal use distinct slots and shape changes stay local" {
    var a = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n A[One]\n B[Two]" });
    defer a.deinit();
    var b = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n A((One))\n C[Three]" });
    defer b.deinit();
    var view = View{};
    var before = P.Snapshot{};
    var after = P.Snapshot{};
    var bytes: [32768]u8 = undefined;
    var patch_bytes: [32768]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var output = gui.html.Writer{ .buffer = &patch_bytes };
    var patches = gui.patch.Writer{ .output = &output };
    var p = P{ .html = &html, .next = &before };
    try view.project(&p, .{ .scene = &a, .namespace = ns, .description = "Example" });
    html.len = 0;
    p = .{ .html = &html, .next = &after, .previous = &before, .patches = &patches, .writing = false };
    try view.project(&p, .{ .scene = &b, .namespace = ns, .description = "Example" });
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "D\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "J\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "H\t103\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.slice(), "H\t100\t") == null);
}

test "diagram namespaces marker IDs and sequence output are independent" {
    var scene = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "sequenceDiagram\n A->>+B: Hello\n B-->>-A: Reply" });
    defer scene.deinit();
    var one = View{};
    var two = View{};
    var snapshot = gui.Projection(View.snapshot_capacity * 2).Snapshot{};
    var bytes: [65536]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var p = gui.Projection(View.snapshot_capacity * 2){ .html = &html, .next = &snapshot };
    try one.project(&p, .{ .scene = &scene, .namespace = ns, .description = "First exchange" });
    try two.project(&p, .{ .scene = &scene, .namespace = .{ .first = 1000, .count = View.node_count }, .description = "Second exchange" });
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "url(#zg-diagram-100-arrow)") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "url(#zg-diagram-1000-arrow)") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "stroke-dasharray=\"5,5\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "zig-diagram-activation") != null);
}

test "diagram admission and writer exhaustion leave identity state available for retry" {
    var scene = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n A --> B" });
    defer scene.deinit();
    var view = View{};
    var snapshot = P.Snapshot{};
    var bytes: [65536]u8 = undefined;
    var html = gui.html.Writer{ .buffer = bytes[0..8] };
    var p = P{ .html = &html, .next = &snapshot };
    try std.testing.expectError(error.OutputOverflow, view.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Example" }));
    try std.testing.expectEqual(@as(usize, 0), html.len);
    try std.testing.expectEqual(@as(usize, 0), snapshot.len);
    try std.testing.expectEqual(@as(usize, 0), view.keys.count());
    html = .{ .buffer = &bytes };
    try std.testing.expectError(error.InvalidNamespace, view.project(&p, .{ .scene = &scene, .namespace = .{ .first = std.math.maxInt(u32), .count = View.node_count }, .description = "Example" }));
    try std.testing.expectEqual(@as(usize, 0), html.len);
    try view.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Example" });
    const accepted = view.keys.count();
    var before = snapshot;
    snapshot = .{};
    var patch_bytes: [4]u8 = undefined;
    var output = gui.html.Writer{ .buffer = &patch_bytes };
    var writer = gui.patch.Writer{ .output = &output };
    html.len = 0;
    p = .{ .html = &html, .next = &snapshot, .previous = &before, .patches = &writer, .writing = false };
    try std.testing.expectError(error.OutputOverflow, view.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Changed" }));
    try std.testing.expectEqual(accepted, view.keys.count());
    try std.testing.expectEqual(@as(usize, 0), output.len);
    var tiny_snapshot = gui.Projection(1).Snapshot{};
    html = .{ .buffer = &bytes };
    var tiny = gui.Projection(1){ .html = &html, .next = &tiny_snapshot };
    try std.testing.expectError(error.OutputOverflow, view.project(&tiny, .{ .scene = &scene, .namespace = ns, .description = "Example" }));
    try std.testing.expectEqual(@as(usize, 0), tiny_snapshot.len);
}

test "diagram public build registration works in an independent consumer package" {
    const options = @import("diagram_test_options");
    const a = std.testing.allocator;
    const io = std.testing.io;
    const directory = ".zig-cache/tmp_diagram_consumer";
    try std.Io.Dir.cwd().createDirPath(io, directory);
    defer std.Io.Dir.cwd().deleteTree(io, directory) catch {};
    const consumer_root = try std.Io.Dir.path.resolve(a, &.{ options.gui_root, directory });
    defer a.free(consumer_root);
    const engine_root = try std.Io.Dir.path.resolve(a, &.{ options.gui_root, options.engine_root });
    defer a.free(engine_root);
    const gui_path = try std.Io.Dir.path.relative(a, options.gui_root, null, consumer_root, options.gui_root);
    defer a.free(gui_path);
    const engine_path = try std.Io.Dir.path.relative(a, options.gui_root, null, consumer_root, engine_root);
    defer a.free(engine_path);
    const zon = try std.fmt.allocPrint(a,
        \\.{{ .name = .diagram_consumer, .version = "0.0.0", .fingerprint = 0x9275d53a27c8fd66, .minimum_zig_version = "0.17.0",
        \\ .dependencies = .{{ .zg_gui = .{{ .path = "{s}" }}, .engine = .{{ .path = "{s}" }} }},
        \\ .paths = .{{ "build.zig", "build.zig.zon", "main.zig" }} }}
    , .{ gui_path, engine_path });
    defer a.free(zon);
    try writeFixture(directory ++ "/build.zig.zon", zon);
    try writeFixture(directory ++ "/build.zig",
        \\const std = @import("std");
        \\pub fn build(b: *std.Build) void {
        \\ const target = b.standardTargetOptions(.{});
        \\ const dep = b.dependency("zg_gui", .{ .target = target, .optimize = std.builtin.OptimizeMode.debug });
        \\ const engine = b.dependency("engine", .{ .target = target, .optimize = std.builtin.OptimizeMode.debug });
        \\ const adapter = @import("zg_gui").addDiagrams(b, .{ .dependency = dep, .engine = engine.module("mermaid") });
        \\ const tests = b.addTest(.{ .root_module = b.createModule(.{
        \\  .root_source_file = b.path("main.zig"), .target = target,
        \\  .imports = &.{ .{ .name = "zg_gui", .module = dep.module("zg_gui") }, .{ .name = "diagrams", .module = adapter } },
        \\ }) });
        \\ b.getInstallStep().dependOn(&b.addRunArtifact(tests).step);
        \\}
    );
    try writeFixture(directory ++ "/main.zig",
        \\const std = @import("std");
        \\const gui = @import("zg_gui");
        \\const diagrams = @import("diagrams");
        \\test "external diagram projection" {
        \\ var scene = try diagrams.engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph LR\n A --> B" });
        \\ defer scene.deinit();
        \\ const View = diagrams.Diagram(32, 128);
        \\ const P = gui.Projection(View.snapshot_capacity);
        \\ var view = View{};
        \\ var snapshot = P.Snapshot{};
        \\ var bytes: [16384]u8 = undefined;
        \\ var html = gui.html.Writer{ .buffer = &bytes };
        \\ var p = P{ .html = &html, .next = &snapshot };
        \\ try view.project(&p, .{ .scene = &scene, .namespace = .{ .first = 1, .count = View.node_count }, .description = "External graph" });
        \\ try std.testing.expect(!html.failed);
        \\ try std.testing.expect(std.mem.indexOf(u8, html.slice(), "marker-end") != null);
        \\}
    );
    var child = try std.process.spawn(io, .{ .argv = &.{ "zig", "build", "-j2" }, .cwd = .{ .path = directory }, .stdout = .inherit, .stderr = .inherit });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));
}

fn writeFixture(path: []const u8, text: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(std.testing.io, path, .{});
    defer file.close(std.testing.io);
    try file.writeStreamingAll(std.testing.io, text);
}

test "diagram admission refuses capacity key collisions and invalid geometry before output" {
    var scene = try engine.buildScene(.{ .allocator = std.testing.allocator, .source = "graph TD\n A --> B" });
    defer scene.deinit();
    var bytes: [16384]u8 = undefined;
    var html = gui.html.Writer{ .buffer = &bytes };
    var snapshot = P.Snapshot{};
    var p = P{ .html = &html, .next = &snapshot };
    var small = diagrams.Diagram(1, 128){};
    try std.testing.expectError(error.CapacityExceeded, small.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Example" }));
    var short = diagrams.Diagram(64, 1){};
    try std.testing.expectError(error.KeyTooLong, short.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Example" }));
    var view = View{};
    const old_key = scene.elements.items[1].key;
    scene.elements.items[1].key = scene.elements.items[0].key;
    try std.testing.expectError(error.DuplicateKey, view.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Example" }));
    scene.elements.items[1].key = old_key;
    scene.width = std.math.nan(f32);
    try std.testing.expectError(error.InvalidGeometry, view.project(&p, .{ .scene = &scene, .namespace = ns, .description = "Example" }));
    try std.testing.expectEqual(@as(usize, 0), html.len);
    try std.testing.expectEqual(@as(usize, 0), snapshot.len);
    try std.testing.expectEqual(@as(usize, 0), view.keys.count());
}
