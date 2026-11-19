const std = @import("std");
const builtin = @import("builtin");

pub const WebAppFeatures = @import("build_web.zig").Features;
pub const addWebApp = @import("build_web.zig").addWebApp;

fn templateImports(tokenizer: *std.Build.Dependency) [2]std.Build.Module.Import {
    return .{
        .{ .name = "html-tokenizer", .module = tokenizer.module("html-tokenizer") },
        .{ .name = "template-syntax", .module = tokenizer.module("template-syntax") },
    };
}

pub fn build(b: *std.Build) void {
    const version = std.mem.trim(u8, @embedFile(".zigversion"), " \t\r\n");
    if (!std.mem.eql(u8, builtin.zig_version_string, version)) {
        std.debug.print("zg-gui requires Zig {s}; found {s}\n", .{ version, builtin.zig_version_string });
        std.process.exit(1);
    }
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const diagrams_enabled = b.option(bool, "diagrams", "Build the optional diagram example and checks") orelse false;
    const browser_filter = b.option([]const u8, "browser-filter", "Run browser tests whose names contain this text");
    const tokenizer = b.dependency("zig_html_tokenizer", .{ .target = b.graph.host, .optimize = .safe });
    const test_tokenizer = b.dependency("zig_html_tokenizer", .{ .target = b.graph.host, .optimize = .debug });
    const compiler_imports = templateImports(tokenizer);
    const test_compiler_imports = templateImports(test_tokenizer);
    const tokenizer_tests = b.step("test-tokenizers", "Test the HTML tokenizer and template syntax utilities");
    for ([_][]const u8{ "syntax-types", "html-tokenizer", "template-syntax" }) |name| {
        const tests = b.addTest(.{ .root_module = test_tokenizer.module(name) });
        tokenizer_tests.dependOn(&b.addRunArtifact(tests).step);
    }
    inline for (.{ "LICENSE", "NOTICE" }) |file| {
        b.getInstallStep().dependOn(&b.addInstallFile(tokenizer.path(file), "share/licenses/zig-html-tokenizer/" ++ file).step);
    }
    const template_compiler = b.addExecutable(.{
        .name = "zg-template",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template/main.zig"),
            .target = b.graph.host,
            .optimize = .safe,
            .imports = &compiler_imports,
        }),
    });
    b.installArtifact(template_compiler);

    const template_formatter = b.addExecutable(.{
        .name = "zg-fmt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template/main.zig"),
            .target = b.graph.host,
            .optimize = .safe,
            .imports = &compiler_imports,
        }),
    });
    b.installArtifact(template_formatter);

    const fmt_step = b.step("fmt", "Format GUI template files");
    const run_fmt = b.addRunArtifact(template_formatter);
    run_fmt.addPassthruArgs();
    fmt_step.dependOn(&run_fmt.step);
    const compiler_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template/compiler.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &test_compiler_imports,
        }),
    });
    const formatter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template/formatter.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &test_compiler_imports,
        }),
    });
    const template_tests = b.step("test-templates", "Test template validation and code generation");
    template_tests.dependOn(&b.addRunArtifact(compiler_tests).step);
    template_tests.dependOn(&b.addRunArtifact(formatter_tests).step);
    const template_compiler_cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/template_compiler_test.zig"),
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    const run_template_compiler_cli_tests = b.addRunArtifact(template_compiler_cli_tests);
    run_template_compiler_cli_tests.setCwd(b.path("."));
    run_template_compiler_cli_tests.step.dependOn(&b.addInstallArtifact(template_compiler, .{}).step);
    run_template_compiler_cli_tests.step.dependOn(&b.addInstallArtifact(template_formatter, .{}).step);
    template_tests.dependOn(&run_template_compiler_cli_tests.step);
    const fixture_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/view.gui.html") });
    const component_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/components.gui.html"), .components = &.{
        .{ .name = "field", .source = b.path("tests/templates/field.gui.html") },
        .{ .name = "wrapped", .source = b.path("tests/templates/wrapped-field.gui.html") },
    } });
    const list_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/list.gui.html") });
    const row_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/list_row.gui.html"), .fragment_context = .ul });
    const radio_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/radio.gui.html") });
    const svg_chart_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/svg_chart.gui.html") });
    const svg_filter_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/svg_filter.gui.html") });
    const svg_marker_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/svg_marker.gui.html") });
    const time_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/time.gui.html") });
    const link_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/link.gui.html") });
    const image_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/image.gui.html") });
    const style_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/style.gui.html") });
    const drag_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/drag.gui.html") });
    const navigation_slot_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/navigation_slot.gui.html") });
    const description_list_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/description_list.gui.html") });
    const tab_order_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/tab_order.gui.html") });
    const aside_slot_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/aside_slot.gui.html") });
    const list_item_slot_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/list_item_slot.gui.html") });
    const native_constraints_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/native_constraints.gui.html") });
    const object_image_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/object_image.gui.html") });
    const table_spans_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/table_spans.gui.html") });
    const form_metadata_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/form_metadata.gui.html") });
    const input_type_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/input_type.gui.html") });
    const navigation_link_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/navigation_link.gui.html") });
    const external_link_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/external_link.gui.html") });
    const embedded_document_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/embedded_document.gui.html") });
    const phrasing_slot_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/phrasing_slot.gui.html") });
    const description_slot_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/description_slot.gui.html") });
    const progress_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/progress.gui.html") });
    const meter_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/meter.gui.html") });
    const option_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/option.gui.html"), .fragment_context = .optgroup });
    const option_group_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/option_group.gui.html"), .fragment_context = .select });
    const select_slot_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/select_slot.gui.html") });
    const table_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/table.gui.html") });
    const table_row_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/table_row.gui.html"), .fragment_context = .tbody });
    const table_cells_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/table_cells.gui.html"), .fragment_context = .tr });
    const table_slot_row_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/table_slot_row.gui.html"), .fragment_context = .tbody });
    const nested_loop_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/nested_loop.gui.html") });
    const multi_select_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/multi_select.gui.html") });
    const loop_components_source = generateTemplate(b, .{
        .compiler = template_compiler,
        .source = b.path("tests/templates/loop_components.gui.html"),
        .components = &.{
            .{ .name = "field", .source = b.path("tests/templates/field.gui.html") },
        },
    });
    const test_gui = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = .debug });
    const generated_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/templates/generated_test.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{
                .{ .name = "zg_gui", .module = test_gui },
                .{ .name = "svg_filter", .module = b.createModule(.{ .root_source_file = svg_filter_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "svg_marker", .module = b.createModule(.{ .root_source_file = svg_marker_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "svg_chart", .module = b.createModule(.{ .root_source_file = svg_chart_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "loop_components_fixture", .module = b.createModule(.{ .root_source_file = loop_components_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "multi_select_fixture", .module = b.createModule(.{ .root_source_file = multi_select_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "nested_loop_fixture", .module = b.createModule(.{ .root_source_file = nested_loop_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "table_cells", .module = b.createModule(.{ .root_source_file = table_cells_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "table_slot_row", .module = b.createModule(.{ .root_source_file = table_slot_row_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "radio_fixture", .module = b.createModule(.{ .root_source_file = radio_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "time_fixture", .module = b.createModule(.{ .root_source_file = time_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "link_fixture", .module = b.createModule(.{ .root_source_file = link_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "image_fixture", .module = b.createModule(.{ .root_source_file = image_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "style_fixture", .module = b.createModule(.{ .root_source_file = style_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "drag_fixture", .module = b.createModule(.{ .root_source_file = drag_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "navigation_slot", .module = b.createModule(.{ .root_source_file = navigation_slot_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "description_list", .module = b.createModule(.{ .root_source_file = description_list_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "tab_order", .module = b.createModule(.{ .root_source_file = tab_order_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "aside_slot", .module = b.createModule(.{ .root_source_file = aside_slot_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "list_item_slot", .module = b.createModule(.{ .root_source_file = list_item_slot_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "native_constraints", .module = b.createModule(.{ .root_source_file = native_constraints_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "object_image", .module = b.createModule(.{ .root_source_file = object_image_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "input_type", .module = b.createModule(.{ .root_source_file = input_type_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "table_spans", .module = b.createModule(.{ .root_source_file = table_spans_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "form_metadata", .module = b.createModule(.{ .root_source_file = form_metadata_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "navigation_link", .module = b.createModule(.{ .root_source_file = navigation_link_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "external_link", .module = b.createModule(.{ .root_source_file = external_link_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "embedded_document", .module = b.createModule(.{ .root_source_file = embedded_document_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "phrasing_slot", .module = b.createModule(.{ .root_source_file = phrasing_slot_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "description_slot", .module = b.createModule(.{ .root_source_file = description_slot_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "progress", .module = b.createModule(.{ .root_source_file = progress_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "meter", .module = b.createModule(.{ .root_source_file = meter_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "option", .module = b.createModule(.{ .root_source_file = option_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "option_group", .module = b.createModule(.{ .root_source_file = option_group_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "select_slot", .module = b.createModule(.{ .root_source_file = select_slot_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "table", .module = b.createModule(.{ .root_source_file = table_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "table_row", .module = b.createModule(.{ .root_source_file = table_row_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "list", .module = b.createModule(.{ .root_source_file = list_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "list_row", .module = b.createModule(.{ .root_source_file = row_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                .{ .name = "components", .module = b.createModule(.{
                    .root_source_file = component_source,
                    .target = b.graph.host,
                    .optimize = .debug,
                    .imports = &.{.{ .name = "zg_gui", .module = test_gui }},
                }) },
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
    _ = b.addModule("zg_charts", .{ .root_source_file = b.path("src/charts.zig"), .target = target, .optimize = optimize });
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

    const bench_module = b.createModule(.{
        .root_source_file = b.path("tests/snapshot_benchmark.zig"),
        .target = b.graph.host,
        .optimize = .fast,
        .imports = &.{.{ .name = "zg_gui", .module = test_gui }},
    });
    const bench_exe = b.addExecutable(.{
        .name = "snapshot-bench",
        .root_module = bench_module,
    });
    const run_bench = b.addRunArtifact(bench_exe);
    b.step("bench", "Run snapshot benchmark").dependOn(&run_bench.step);

    b.installDirectory(.{ .source_dir = b.path("web"), .install_dir = .prefix, .install_subdir = "web" });

    const wasm_target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const math_check = b.step("test-math", "Test optional math ownership without a core provider dependency");
    const math_fixture = b.createModule(.{ .root_source_file = b.path("tests/math_provider.zig"), .target = b.graph.host, .optimize = optimize });
    const math_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/math.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "math_typesetter", .module = math_fixture }},
    }) });
    math_check.dependOn(&b.addRunArtifact(math_tests).step);
    const math_wasm = b.addExecutable(.{ .name = "math-optional-check", .root_module = b.createModule(.{
        .root_source_file = b.path("tests/math_wasm.zig"),
        .target = wasm_target,
        .optimize = optimize,
    }) });
    math_wasm.root_module.addImport("zg_math", b.createModule(.{
        .root_source_file = b.path("src/math.zig"),
        .target = wasm_target,
        .optimize = optimize,
        .imports = &.{.{ .name = "math_typesetter", .module = b.createModule(.{ .root_source_file = b.path("tests/math_provider.zig"), .target = wasm_target, .optimize = optimize }) }},
    }));
    math_wasm.entry = .disabled;
    math_wasm.rdynamic = true;
    math_check.dependOn(&math_wasm.step);
    b.top_level_steps.get("test").?.step.dependOn(math_check);
    const controls_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("examples/panels.gui.html"), .components = &.{.{ .name = "controls", .source = b.path("examples/controls.gui.html") }} });
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
                .{ .name = "controls_template", .module = b.createModule(.{
                    .root_source_file = controls_source,
                    .target = wasm_target,
                    .optimize = .safe,
                    .imports = &.{.{ .name = "zg_gui", .module = wasm_gui }},
                }) },
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
                .{ .name = "controls_template", .module = b.createModule(.{
                    .root_source_file = controls_source,
                    .target = b.graph.host,
                    .optimize = .safe,
                    .imports = &.{.{ .name = "zg_gui", .module = test_gui }},
                }) },
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

    const workspace_source = generateTemplate(b, .{
        .compiler = template_compiler,
        .source = b.path("examples/workspace.gui.html"),
        .components = &.{.{ .name = "metric", .source = b.path("examples/workspace-metric.gui.html") }},
    });
    const workspace = b.addExecutable(.{
        .name = "workspace",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/workspace.zig"),
            .target = wasm_target,
            .optimize = .safe,
            .strip = true,
            .imports = &.{
                .{ .name = "zg_gui", .module = wasm_gui },
                .{ .name = "workspace_template", .module = b.createModule(.{
                    .root_source_file = workspace_source,
                    .target = wasm_target,
                    .optimize = .safe,
                    .imports = &.{.{ .name = "zg_gui", .module = wasm_gui }},
                }) },
            },
        }),
    });
    workspace.entry = .disabled;
    workspace.rdynamic = true;
    workspace.export_memory = true;
    workspace.stack_size = 512 * 1024;
    b.getInstallStep().dependOn(&b.addInstallFile(workspace.getEmittedBin(), "web/workspace.wasm").step);
    b.installFile("examples/demo.zig", "web/source/demo.zig");
    b.installFile("examples/demo.gui.html", "web/source/demo.gui.html");
    b.installFile("examples/controls.gui.html", "web/source/controls.gui.html");
    b.installFile("examples/panels.gui.html", "web/source/panels.gui.html");
    b.installFile("examples/workspace.zig", "web/source/workspace.zig");
    b.installFile("examples/workspace.gui.html", "web/source/workspace.gui.html");
    b.installFile("examples/workspace-metric.gui.html", "web/source/workspace-metric.gui.html");
    const workspace_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/workspace.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{
                .{ .name = "zg_gui", .module = test_gui },
                .{ .name = "workspace_template", .module = b.createModule(.{
                    .root_source_file = workspace_source,
                    .target = b.graph.host,
                    .optimize = .debug,
                    .imports = &.{.{ .name = "zg_gui", .module = test_gui }},
                }) },
            },
        }),
    });
    const workspace_check = b.step("test-workspace", "Test the bounded workspace example");
    workspace_check.dependOn(&b.addRunArtifact(workspace_tests).step);
    b.top_level_steps.get("test").?.step.dependOn(workspace_check);

    const charts_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("examples/charts.gui.html"), .components = &.{.{ .name = "plot", .source = b.path("examples/charts-plot.gui.html") }} });
    const charts = b.addExecutable(.{ .name = "charts", .root_module = b.createModule(.{ .root_source_file = b.path("examples/charts.zig"), .target = wasm_target, .optimize = .safe, .strip = true, .imports = &.{ .{ .name = "zg_gui", .module = wasm_gui }, .{ .name = "charts_template", .module = b.createModule(.{ .root_source_file = charts_source, .target = wasm_target, .optimize = .safe, .imports = &.{.{ .name = "zg_gui", .module = wasm_gui }} }) } } }) });
    charts.entry = .disabled;
    charts.rdynamic = true;
    charts.export_memory = true;
    charts.stack_size = 256 * 1024;
    b.getInstallStep().dependOn(&b.addInstallFile(charts.getEmittedBin(), "web/charts.wasm").step);
    const charts_tests = b.addTest(.{ .root_module = b.createModule(.{ .root_source_file = b.path("examples/charts.zig"), .target = b.graph.host, .optimize = .debug, .imports = &.{ .{ .name = "zg_gui", .module = test_gui }, .{ .name = "charts_template", .module = b.createModule(.{ .root_source_file = charts_source, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) } } }) });
    const chart_check = b.step("test-charts", "Test numerical chart example admission and retained projection");
    chart_check.dependOn(&b.addRunArtifact(charts_tests).step);
    b.top_level_steps.get("test").?.step.dependOn(chart_check);
    inline for (.{ "charts.zig", "charts.gui.html", "charts-plot.gui.html" }) |file| b.installFile("examples/" ++ file, "web/source/" ++ file);

    const cdp = b.dependency("zig_cdp", .{
        .target = b.graph.host,
        .optimize = .debug,
    }).module("cdp");
    b.modules.put(b.allocator, "cdp", cdp) catch @panic("OOM");

    const serve_exe = b.addExecutable(.{
        .name = "serve",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/serve.zig"),
            .target = b.graph.host,
            .optimize = .safe,
        }),
    });
    b.installArtifact(serve_exe);
    const run_serve = b.addRunArtifact(serve_exe);
    run_serve.setCwd(b.path("."));
    run_serve.step.dependOn(b.getInstallStep());
    const serve_step = b.step("serve", "Run local development web server");
    serve_step.dependOn(&run_serve.step);

    const tools_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/tools_test.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{.{ .name = "cdp", .module = cdp }},
        }),
    });
    const run_tools_tests = b.addRunArtifact(tools_tests);
    run_tools_tests.setCwd(b.path("."));
    const tools_step = b.step("test-tools", "Test native repository tools and CDP protocol");
    tools_step.dependOn(&run_tools_tests.step);
    b.top_level_steps.get("test").?.step.dependOn(tools_step);

    const browser_options = b.addOptions();
    browser_options.addOption(bool, "diagrams", diagrams_enabled);
    const browser_unit_tests = b.addTest(.{
        .filters = if (browser_filter) |filter| b.allocator.dupe([]const u8, &.{filter}) catch @panic("OOM") else &.{},
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/browser_tests.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{ .{ .name = "cdp", .module = cdp }, .{ .name = "browser_options", .module = browser_options.createModule() } },
        }),
    });
    const run_browser_unit_tests = b.addRunArtifact(browser_unit_tests);
    run_browser_unit_tests.setCwd(b.path("."));
    // Browser journeys consume installed assets and external browser state.
    run_browser_unit_tests.has_side_effects = true;
    run_browser_unit_tests.step.dependOn(b.getInstallStep());
    const browser_unit_step = b.step("test-browser-unit", "Test native CDP browser unit harness");
    browser_unit_step.dependOn(&run_browser_unit_tests.step);

    const browser_step = b.step("test-browser", "Run browser test suites via native CDP");
    browser_step.dependOn(browser_unit_step);

    const test_all_step = b.step("test-all", "Run all tests: core, templates, tools, and browser");
    test_all_step.dependOn(&b.top_level_steps.get("test").?.step);
    test_all_step.dependOn(browser_step);

    const engine_pin = @import("build.zig.zon").dependencies.diagram_engine;
    const verify_engine = b.step("verify-diagram-engine", "Verify the resolved diagram engine against its package hash");
    if (diagrams_enabled) {
        b.getInstallStep().dependOn(verify_engine);

        if (b.lazyDependency("diagram_engine", .{ .target = b.graph.host, .optimize = std.builtin.OptimizeMode.debug })) |dependency| {
            b.getInstallStep().dependOn(&b.addInstallFile(dependency.path("LICENSE"), "share/licenses/zig-mermaid-viewer/LICENSE").step);
            const file_check = b.addRunArtifact(b.addExecutable(.{ .name = "check-diagram-package-files", .root_module = b.createModule(.{
                .root_source_file = b.path("tools/verify_diagram_engine.zig"),
                .target = b.graph.host,
                .optimize = .safe,
            }) }));
            file_check.addDirectoryArg(dependency.path("."));
            file_check.has_side_effects = true;
            const hash_check = b.addSystemCommand(&.{ b.graph.zig_exe, "fetch" });
            hash_check.addDirectoryArg(dependency.path("."));
            hash_check.expectStdOutEqual(engine_pin.hash ++ "\n");
            hash_check.has_side_effects = true;
            hash_check.step.dependOn(&file_check.step);
            verify_engine.dependOn(&hash_check.step);
            const engine = dependency.module("mermaid");
            const options = b.addOptions();
            options.addOption([]const u8, "gui_root", b.root.joinString(b.allocator, "") catch @panic("OOM"));
            options.addOption([]const u8, "engine_url", engine_pin.url);
            options.addOption([]const u8, "engine_hash", engine_pin.hash);
            const diagram_tests = b.addTest(.{ .root_module = b.createModule(.{
                .root_source_file = b.path("tests/diagrams_test.zig"),
                .target = b.graph.host,
                .optimize = .debug,
                .imports = &.{
                    .{ .name = "zg_gui", .module = test_gui },
                    .{ .name = "zg_diagrams", .module = diagramModule(b, .{ .source = b.path("src/diagrams.zig"), .gui = test_gui, .engine = engine }) },
                    .{ .name = "diagram_test_options", .module = options.createModule() },
                },
            }) });
            const run_diagram_tests = b.addRunArtifact(diagram_tests);
            run_diagram_tests.setCwd(b.path("."));
            const step = b.step("test-diagrams", "Verify optional typed diagram projections");
            step.dependOn(&run_diagram_tests.step);
            step.dependOn(verify_engine);
            b.top_level_steps.get("test").?.step.dependOn(step);
            const diagram_template = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("examples/diagrams.gui.html") });
            const native_example = b.addTest(.{ .root_module = b.createModule(.{
                .root_source_file = b.path("examples/diagrams.zig"),
                .target = b.graph.host,
                .optimize = .debug,
                .imports = &.{
                    .{ .name = "zg_gui", .module = test_gui },
                    .{ .name = "zg_diagrams", .module = diagramModule(b, .{ .source = b.path("src/diagrams.zig"), .gui = test_gui, .engine = engine }) },
                    .{ .name = "diagrams_template", .module = b.createModule(.{ .root_source_file = diagram_template, .target = b.graph.host, .optimize = .debug, .imports = &.{.{ .name = "zg_gui", .module = test_gui }} }) },
                },
            }) });
            step.dependOn(&b.addRunArtifact(native_example).step);
            if (b.lazyDependency("diagram_engine", .{ .target = wasm_target, .optimize = std.builtin.OptimizeMode.safe })) |wasm_dependency| {
                const example = b.addExecutable(.{ .name = "diagrams", .root_module = b.createModule(.{
                    .root_source_file = b.path("examples/diagrams.zig"),
                    .target = wasm_target,
                    .optimize = .safe,
                    .strip = true,
                    .imports = &.{
                        .{ .name = "zg_gui", .module = wasm_gui },
                        .{ .name = "zg_diagrams", .module = diagramModule(b, .{ .source = b.path("src/diagrams.zig"), .gui = wasm_gui, .engine = wasm_dependency.module("mermaid") }) },
                        .{ .name = "diagrams_template", .module = b.createModule(.{ .root_source_file = diagram_template, .target = wasm_target, .optimize = .safe, .imports = &.{.{ .name = "zg_gui", .module = wasm_gui }} }) },
                    },
                }) });
                example.entry = .disabled;
                example.rdynamic = true;
                example.export_memory = true;
                example.stack_size = 1024 * 1024;
                b.getInstallStep().dependOn(&b.addInstallFile(example.getEmittedBin(), "web/diagrams.wasm").step);
            }
        }
    } else {
        // The explicit verification command can fetch the optional engine on a core-only checkout.
        const verify_with_engine = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "verify-diagram-engine", "-Ddiagrams=true" });
        verify_with_engine.setCwd(b.path("."));
        if (b.graph.system_package_mode) {
            const installed = tokenizer.builder.root.joinString(b.allocator, "") catch @panic("OOM");
            verify_with_engine.addArgs(&.{ "--system", std.fs.path.dirname(installed) orelse "." });
        }
        verify_with_engine.has_side_effects = true;
        verify_engine.dependOn(&verify_with_engine.step);
    }
}

pub const FragmentContext = enum { flow, dl, ul, ol, thead, tbody, tfoot, tr, select, optgroup };

/// Optional MathML caching through a caller-selected public typesetter module.
/// Core GUI modules do not instantiate a typesetter dependency.
pub fn addMath(b: *std.Build, input: struct { dependency: *std.Build.Dependency, typesetter: *std.Build.Module }) *std.Build.Module {
    const gui = input.dependency.module("zg_gui");
    return b.createModule(.{
        .root_source_file = input.dependency.path("src/math.zig"),
        .target = gui.resolved_target,
        .optimize = gui.optimize,
        .imports = &.{.{ .name = "math_typesetter", .module = input.typesetter }},
    });
}

/// Opt into typed scene projection with an explicitly selected layout module.
/// Core consumers do not instantiate or link an engine dependency.
pub fn addDiagrams(b: *std.Build, input: struct { dependency: *std.Build.Dependency, engine: *std.Build.Module }) *std.Build.Module {
    const gui = input.dependency.module("zg_gui");
    return diagramModule(b, .{ .source = input.dependency.path("src/diagrams.zig"), .gui = gui, .engine = input.engine });
}

fn diagramModule(b: *std.Build, input: struct { source: std.Build.LazyPath, gui: *std.Build.Module, engine: *std.Build.Module }) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = input.source,
        .target = input.gui.resolved_target,
        .optimize = input.gui.optimize,
        .imports = &.{ .{ .name = "zg_gui", .module = input.gui }, .{ .name = "diagram_engine", .module = input.engine } },
    });
}

pub const TemplateComponent = struct { name: []const u8, source: std.Build.LazyPath };

pub fn generateTemplate(b: *std.Build, input: struct { compiler: *std.Build.Step.Compile, source: std.Build.LazyPath, components: []const TemplateComponent = &.{}, fragment_context: FragmentContext = .flow }) std.Build.LazyPath {
    const run = b.addRunArtifact(input.compiler);
    run.addFileArg(input.source);
    const output = run.addOutputFileArg("template.zig");
    run.addArg(b.fmt("--context={s}", .{@tagName(input.fragment_context)}));
    for (input.components) |component| {
        run.addArg(component.name);
        run.addFileArg(component.source);
    }
    return output;
}

/// Compile an application-owned template and register its generated projection.
/// Instantiate dependency with the same target/optimization as owner. Its public
/// zg_gui module is shared with the application when the application imports it.
pub fn addTemplate(b: *std.Build, input: struct {
    dependency: *std.Build.Dependency,
    owner: *std.Build.Module,
    name: []const u8,
    source: std.Build.LazyPath,
    components: []const TemplateComponent = &.{},
    fragment_context: FragmentContext = .flow,
}) void {
    const gui = input.dependency.module("zg_gui");
    const source = generateTemplate(b, .{
        .compiler = input.dependency.artifact("zg-template"),
        .source = input.source,
        .components = input.components,
        .fragment_context = input.fragment_context,
    });
    input.owner.addImport(input.name, b.createModule(.{
        .root_source_file = source,
        .target = gui.resolved_target,
        .optimize = gui.optimize,
        .imports = &.{.{ .name = "zg_gui", .module = gui }},
    }));
}
