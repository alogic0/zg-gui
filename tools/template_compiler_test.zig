//! Native tests for template compiler CLI, provenance, diagnostics, and external packaging.
//! Replaces tests/template-compiler.test.mjs and tests/template-package.test.mjs.
const std = @import("std");

test "template compiler: vendored source hashes remain pinned" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const manifest_path = "vendor/superhtml/provenance.json";
    const content = try std.Io.Dir.cwd().readFileAlloc(io, manifest_path, alloc, .limited(32768));
    defer alloc.free(content);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, content, .{});
    defer parsed.deinit();

    const files_obj = parsed.value.object.get("files").?.object;
    var it = files_obj.iterator();
    while (it.next()) |entry| {
        const rel_path = entry.key_ptr.*;
        const expected_hash = entry.value_ptr.string;

        const target_path = try std.fs.path.join(alloc, &.{ "vendor/superhtml", rel_path });
        defer alloc.free(target_path);

        const data = try std.Io.Dir.cwd().readFileAlloc(io, target_path, alloc, .limited(1024 * 1024));
        defer alloc.free(data);

        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
        const hex = std.fmt.bytesToHex(digest, .lower);

        try std.testing.expectEqualStrings(expected_hash, &hex);
    }
}

test "template compiler: diagnostics preserve output and invalid input fails" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_diag";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/view.gui.html";
    const out_path = tmp_dir ++ "/generated.zig";

    // Write initial successful output
    {
        var out_file = try std.Io.Dir.cwd().createFile(io, out_path, .{});
        defer out_file.close(io);
        try out_file.writeStreamingAll(io, "previous successful artifact");
    }

    // Write bad template
    {
        var src_file = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer src_file.close(io);
        try src_file.writeStreamingAll(io, "<div>\n<span :text=\"$name + bad()\"></span>\n</div>");
    }

    // Run zg-template
    const run_res = std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .pipe,
        .stderr = .pipe,
    }) catch |err| {
        if (err == error.FileNotFound) return;
        return err;
    };
    var child = run_res;
    const term = try child.wait(io);
    try std.testing.expect(term != .exited or term.exited != 0);

    // Verify out_path was NOT modified
    const text = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(256));
    defer alloc.free(text);
    try std.testing.expectEqualStrings("previous successful artifact", text);
}

test "template compiler: list fragment CLI context is explicit and rejection preserves output" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_list";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/row.gui.html";
    const out_path = tmp_dir ++ "/row.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<li :text=\"$label\"></li>");
    }

    for ([_][]const u8{ "ul", "ol" }) |ctx| {
        const ctx_arg = try std.fmt.allocPrint(alloc, "--context={s}", .{ctx});
        defer alloc.free(ctx_arg);
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-template", src_path, out_path, ctx_arg },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }

    // Read accepted output
    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    // Test rejection preserves output
    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path, "--context=div" },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad != .exited or term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: table row contexts preserve output after invalid structure or context" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_table";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/row.gui.html";
    const out_path = tmp_dir ++ "/row.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<tr><td :text=\"$label\"></td></tr>");
    }

    for ([_][]const u8{ "thead", "tbody", "tfoot" }) |ctx| {
        const ctx_arg = try std.fmt.allocPrint(alloc, "--context={s}", .{ctx});
        defer alloc.free(ctx_arg);
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-template", src_path, out_path, ctx_arg },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }

    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path, "--context=table" },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad != .exited or term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: navigation slot rejection preserves successful generated output" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_nav";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/nav.gui.html";
    const out_path = tmp_dir ++ "/nav.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<nav aria-label=\"Sections\" :slot=\"$children\"></nav>");
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));

    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    // Invalid nav slot child
    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<nav :slot=\"$children\">text</nav>");
    }

    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad == .exited and term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: aside slot rejection preserves successful generated output" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_aside";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/aside.gui.html";
    const out_path = tmp_dir ++ "/aside.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<aside aria-label=\"Sections\" :slot=\"$children\"></aside>");
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));

    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<aside :slot=\"$children\">text</aside>");
    }

    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad == .exited and term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: cell context rejects invalid roots without replacing generated output" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_cells";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/cells.gui.html";
    const out_path = tmp_dir ++ "/cells.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<th :text=\"$label\"></th><td><input :value=\"$draft\"></td>");
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path, "--context=tr" },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));

    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<tr><td>Nested</td></tr>");
    }

    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path, "--context=tr" },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad == .exited and term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: dynamic progress rejection preserves accepted compiler output" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_progress";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/progress.gui.html";
    const out_path = tmp_dir ++ "/progress.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<progress max=\"$maximum\" value=\"$level\"></progress>");
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));

    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<progress max=\"$maximum\"></progress>");
    }

    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad == .exited and term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: dynamic table spans are restricted to cells" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_spans";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/view.gui.html";
    const out_path = tmp_dir ++ "/view.zig";

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<table><tbody><tr><th colspan=\"$columns\">Title</th><td rowspan=\"$rows\">Value</td></tr></tbody></table>");
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));

    const accepted = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(accepted);

    {
        var sf = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer sf.close(io);
        try sf.writeStreamingAll(io, "<div colspan=\"$columns\"></div>");
    }

    var child_bad = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", src_path, out_path },
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const term_bad = try child_bad.wait(io);
    try std.testing.expect(term_bad == .exited and term_bad.exited != 0);

    const curr = try std.Io.Dir.cwd().readFileAlloc(io, out_path, alloc, .limited(65536));
    defer alloc.free(curr);
    try std.testing.expectEqualStrings(accepted, curr);
}

test "template compiler: independent Zig package compiles and imports its own HTML template" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_pkg";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const root_dir = try std.fs.path.resolve(alloc, &.{"."});
    defer alloc.free(root_dir);

    // build.zig.zon
    {
        const zon_content =
            \\.{
            \\    .name = .gui_consumer,
            \\    .version = "0.0.0",
            \\    .fingerprint = 0x3d0af40a357f117c,
            \\    .dependencies = .{
            \\        .zg_gui = .{ .path = "../.." },
            \\    },
            \\    .paths = .{ "build.zig", "build.zig.zon", "main.zig", "view.gui.html", "field.gui.html", "row.gui.html" },
            \\}
            \\
        ;
        var f = try std.Io.Dir.cwd().createFile(io, tmp_dir ++ "/build.zig.zon", .{});
        defer f.close(io);
        try f.writeStreamingAll(io, zon_content);
    }

    {
        var f = try std.Io.Dir.cwd().createFile(io, tmp_dir ++ "/row.gui.html", .{});
        defer f.close(io);
        try f.writeStreamingAll(io, "<tr><td :text=\"$label\"></td></tr>");
    }

    {
        var f = try std.Io.Dir.cwd().createFile(io, tmp_dir ++ "/view.gui.html", .{});
        defer f.close(io);
        try f.writeStreamingAll(io, "<template :component=\"field\" :view=\"$first\" :ref=\"first\"></template><template :component=\"field\" :view=\"$second\" :ref=\"second\"></template>");
    }

    {
        var f = try std.Io.Dir.cwd().createFile(io, tmp_dir ++ "/field.gui.html", .{});
        defer f.close(io);
        try f.writeStreamingAll(io, "<output :ref=\"value\" :text=\"$count\"></output>");
    }

    {
        const build_content =
            \\const std = @import("std");
            \\pub fn build(b: *std.Build) void {
            \\    const target = b.standardTargetOptions(.{});
            \\    const dep = b.dependency("zg_gui", .{ .target = target, .optimize = std.builtin.OptimizeMode.debug });
            \\    const gui = dep.module("zg_gui");
            \\    const tests = b.addTest(.{ .root_module = b.createModule(.{
            \\        .root_source_file = b.path("main.zig"), .target = target,
            \\        .imports = &.{.{ .name = "zg_gui", .module = gui }} }) });
            \\    @import("zg_gui").addTemplate(b, .{ .dependency = dep, .owner = tests.root_module, .name = "view", .source = b.path("view.gui.html"), .components = &.{.{ .name = "field", .source = b.path("field.gui.html") }} });
            \\    @import("zg_gui").addTemplate(b, .{ .dependency = dep, .owner = tests.root_module, .name = "row", .source = b.path("row.gui.html"), .fragment_context = .tbody });
            \\    b.getInstallStep().dependOn(&b.addRunArtifact(tests).step);
            \\}
        ;
        var f = try std.Io.Dir.cwd().createFile(io, tmp_dir ++ "/build.zig", .{});
        defer f.close(io);
        try f.writeStreamingAll(io, build_content);
    }

    {
        const main_content =
            \\const std = @import("std");
            \\const gui = @import("zg_gui");
            \\const template = @import("view");
            \\test "external generated template" {
            \\    var bytes: [256]u8 = undefined;
            \\    var html = gui.html.Writer{ .buffer = &bytes };
            \\    const P = gui.Projection(template.snapshot_capacity);
            \\    var snapshot = P.Snapshot{};
            \\    var p = P{ .html = &html, .next = &snapshot };
            \\    template.project(&p, .{ .first = .{ .count = @as(u32, 42) }, .second = .{ .count = @as(u32, 7) } });
            \\    try std.testing.expect(!html.failed);
            \\    html.len = 0; snapshot = .{};
            \\    @import("row").project(&p, .{ .label = "cell" });
            \\    try std.testing.expect(std.mem.indexOf(u8, html.slice(), ">cell</td>") != null);
            \\    html.len = 0; snapshot = .{};
            \\    template.project(&p, .{ .first = .{ .count = @as(u32, 42) }, .second = .{ .count = @as(u32, 7) } });
            \\    try std.testing.expectEqual(@as(usize, 2), template.snapshot_capacity);
            \\    try std.testing.expect(template.nodes.@"first.value" != template.nodes.@"second.value");
            \\    try std.testing.expect(std.mem.indexOf(u8, html.slice(), ">7</output>") != null);
            \\    try std.testing.expect(std.mem.indexOf(u8, html.slice(), "<template") == null);
            \\    try std.testing.expect(std.mem.indexOf(u8, html.slice(), ">42</output>") != null);
            \\}
        ;
        var f = try std.Io.Dir.cwd().createFile(io, tmp_dir ++ "/main.zig", .{});
        defer f.close(io);
        try f.writeStreamingAll(io, main_content);
    }

    // Run zig build
    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig", "build" },
        .cwd = .{ .path = tmp_dir },
        .stdout = .inherit,
        .stderr = .inherit,
    });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, try child.wait(io));
}

test "template formatter: CLI in-place write (-w) and check mode (-c)" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_fmt_check";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/button.gui.html";
    const unformatted = "<div><button :ref=\"btn\" :on-click=\"$click\">Click</button></div>\n";

    {
        var f = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer f.close(io);
        try f.writeStreamingAll(io, unformatted);
    }

    // 1. zg-fmt -c should fail with exit code != 0
    {
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-fmt", "-c", src_path },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expect(term != .exited or term.exited != 0);
    }

    // 2. zg-template fmt -c should also fail
    {
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-template", "fmt", "-c", src_path },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expect(term != .exited or term.exited != 0);
    }

    // 3. zg-fmt -w should format in-place
    {
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-fmt", "-w", src_path },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }

    // Verify formatted content
    const expected =
        \\<div>
        \\  <button :ref="btn" :on-click="$click">Click</button>
        \\</div>
        \\
    ;
    const on_disk = try std.Io.Dir.cwd().readFileAlloc(io, src_path, alloc, .limited(4096));
    defer alloc.free(on_disk);
    try std.testing.expectEqualStrings(expected, on_disk);

    // 4. zg-fmt -c should now succeed
    {
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-fmt", "-c", src_path },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }

    // 5. zg-template fmt -c should now succeed
    {
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig-out/bin/zg-template", "fmt", "-c", src_path },
            .stdout = .ignore,
            .stderr = .ignore,
        });
        const term = try child.wait(io);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);
    }
}

test "template formatter: CLI stdout output" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_fmt_stdout";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/card.gui.html";
    const unformatted = "<section class=\"card\"><span>Header</span></section>";

    {
        var f = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer f.close(io);
        try f.writeStreamingAll(io, unformatted);
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-template", "fmt", src_path },
        .stdout = .pipe,
        .stderr = .ignore,
    });
    var stdout_pipe = child.stdout.?;
    var buf: [1024]u8 = undefined;
    var reader = stdout_pipe.reader(io, &buf);
    const output = try reader.interface.allocRemaining(alloc, .limited(4096));
    defer alloc.free(output);

    const term = try child.wait(io);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, term);

    const expected =
        \\<section class="card">
        \\  <span>Header</span>
        \\</section>
        \\
    ;
    try std.testing.expectEqualStrings(expected, output);

    // Verify source file on disk was not modified
    const disk_content = try std.Io.Dir.cwd().readFileAlloc(io, src_path, alloc, .limited(4096));
    defer alloc.free(disk_content);
    try std.testing.expectEqualStrings(unformatted, disk_content);
}

test "template formatter: CLI diagnostics on invalid template" {
    const alloc = std.testing.allocator;
    const io = std.testing.io;

    const tmp_dir = ".zig-cache/tmp_template_fmt_err";
    try std.Io.Dir.cwd().createDirPath(io, tmp_dir);
    defer std.Io.Dir.cwd().deleteTree(io, tmp_dir) catch {};

    const src_path = tmp_dir ++ "/invalid.gui.html";
    {
        var f = try std.Io.Dir.cwd().createFile(io, src_path, .{});
        defer f.close(io);
        try f.writeStreamingAll(io, "<div><span>mismatch</div></span>");
    }

    var child = try std.process.spawn(io, .{
        .argv = &.{ "zig-out/bin/zg-fmt", src_path },
        .stdout = .ignore,
        .stderr = .pipe,
    });
    var stderr_pipe = child.stderr.?;
    var buf: [1024]u8 = undefined;
    var reader = stderr_pipe.reader(io, &buf);
    const err_out = try reader.interface.allocRemaining(alloc, .limited(4096));
    defer alloc.free(err_out);

    const term = try child.wait(io);
    try std.testing.expect(term != .exited or term.exited != 0);
    try std.testing.expect(std.mem.indexOf(u8, err_out, "mismatched closing tag") != null);
}

