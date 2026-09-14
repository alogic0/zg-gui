const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const version = std.mem.trim(u8, @embedFile(".zigversion"), " \t\r\n");
    if (!std.mem.eql(u8, builtin.zig_version_string, version)) {
        std.debug.print("zg-gui requires Zig {s}; found {s}\n", .{ version, builtin.zig_version_string });
        std.process.exit(1);
    }
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const syntax_types = b.createModule(.{
        .root_source_file = b.path("vendor/superhtml/src/syntax_types.zig"),
        .target = b.graph.host,
    });
    const html_tokenizer = b.createModule(.{
        .root_source_file = b.path("vendor/superhtml/src/html_tokenizer.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "syntax-types", .module = syntax_types }},
    });
    const template_syntax = b.createModule(.{
        .root_source_file = b.path("vendor/superhtml/src/template_syntax.zig"),
        .target = b.graph.host,
        .imports = &.{.{ .name = "html-tokenizer", .module = html_tokenizer }},
    });
    const tokenizer_tests = b.step("test-tokenizers", "Test the vendored HTML tokenizer and syntax utilities");
    for ([_]*std.Build.Module{ syntax_types, html_tokenizer, template_syntax }) |module| {
        const tests = b.addTest(.{ .root_module = module });
        tokenizer_tests.dependOn(&b.addRunArtifact(tests).step);
    }
    const compiler_imports: []const std.Build.Module.Import = &.{
        .{ .name = "html-tokenizer", .module = html_tokenizer },
        .{ .name = "template-syntax", .module = template_syntax },
    };
    const template_compiler = b.addExecutable(.{
        .name = "zg-template",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template/main.zig"),
            .target = b.graph.host,
            .optimize = .safe,
            .imports = compiler_imports,
        }),
    });
    b.installArtifact(template_compiler);
    const compiler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template/compiler.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = compiler_imports,
        }),
    });
    const template_tests = b.step("test-templates", "Test template validation and code generation");
    template_tests.dependOn(&b.addRunArtifact(compiler_tests).step);
    const fixture_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/view.gui.html") });
    const test_gui = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = .debug });
    const generated_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/templates/generated_test.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{
                .{ .name = "zg_gui", .module = test_gui },
                .{ .name = "fixture", .module = b.createModule(.{
                    .root_source_file = fixture_source,
                    .target = b.graph.host,
                    .optimize = .debug,
                    .imports = &.{.{ .name = "zg_gui", .module = test_gui }},
                }) },
            },
        }),
    });
    template_tests.dependOn(&b.addRunArtifact(generated_tests).step);
    _ = b.addModule("zg_gui", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    b.step("test", "Test the GUI core").dependOn(&b.addRunArtifact(unit_tests).step);
    b.top_level_steps.get("test").?.step.dependOn(tokenizer_tests);
    b.top_level_steps.get("test").?.step.dependOn(template_tests);
    b.installDirectory(.{ .source_dir = b.path("web"), .install_dir = .prefix, .install_subdir = "web" });

    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const demo_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("examples/demo.gui.html") });
    const wasm_gui = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = wasm_target, .optimize = .safe });
    const demo = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = wasm_target,
            .optimize = .safe,
            .strip = true,
            .imports = &.{
                .{ .name = "zg_gui", .module = wasm_gui },
                .{ .name = "demo_template", .module = b.createModule(.{
                    .root_source_file = demo_source,
                    .target = wasm_target,
                    .optimize = .safe,
                    .imports = &.{.{ .name = "zg_gui", .module = wasm_gui }},
                }) },
            },
        }),
    });
    demo.entry = .disabled;
    demo.rdynamic = true;
    demo.export_memory = true;
    demo.stack_size = 64 * 1024;
    b.getInstallStep().dependOn(&b.addInstallFile(demo.getEmittedBin(), "web/demo.wasm").step);
    b.installDirectory(.{ .source_dir = b.path("examples/web"), .install_dir = .prefix, .install_subdir = "web" });
    const demo_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/demo.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{
                .{ .name = "zg_gui", .module = test_gui },
                .{ .name = "demo_template", .module = b.createModule(.{
                    .root_source_file = demo_source,
                    .target = b.graph.host,
                    .optimize = .debug,
                    .imports = &.{.{ .name = "zg_gui", .module = test_gui }},
                }) },
            },
        }),
    });
    b.top_level_steps.get("test").?.step.dependOn(&b.addRunArtifact(demo_tests).step);
}

pub fn generateTemplate(b: *std.Build, input: struct { compiler: *std.Build.Step.Compile, source: std.Build.LazyPath }) std.Build.LazyPath {
    const run = b.addRunArtifact(input.compiler);
    run.addFileArg(input.source);
    return run.addOutputFileArg("template.zig");
}
