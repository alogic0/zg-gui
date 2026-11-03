const std = @import("std");

const release_version = "0.9.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mermaid = b.addModule("mermaid", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("mermaid_viewer", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    _ = b.addModule("drawing", .{
        .root_source_file = b.path("src/drawing.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Sub-libraries planned in PLAN.md exported for independent consumption
    _ = b.addModule("graph", .{
        .root_source_file = b.path("src/graph.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("font_metrics", .{
        .root_source_file = b.path("src/font_metrics.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("svg", .{
        .root_source_file = b.path("src/svg.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("flowchart_parser", .{
        .root_source_file = b.path("src/flowchart_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("sequence_parser", .{
        .root_source_file = b.path("src/sequence_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("sequence_layout", .{
        .root_source_file = b.path("src/sequence_layout.zig"),
        .target = target,
        .optimize = optimize,
    });
    _ = b.addModule("sugiyama_layout", .{
        .root_source_file = b.path("src/sugiyama_layout.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests = b.addTest(.{ .root_module = mermaid });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run Mermaid viewer tests");
    test_step.dependOn(&run_tests.step);
}
