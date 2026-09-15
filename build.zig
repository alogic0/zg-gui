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
    const component_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/components.gui.html"), .components = &.{
        .{ .name = "field", .source = b.path("tests/templates/field.gui.html") },
        .{ .name = "wrapped", .source = b.path("tests/templates/wrapped-field.gui.html") },
    } });
    const list_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/list.gui.html") });
    const row_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/list_row.gui.html"), .fragment_context = .ul });
    const radio_source = generateTemplate(b, .{ .compiler = template_compiler, .source = b.path("tests/templates/radio.gui.html") });
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
    const test_gui = b.createModule(.{ .root_source_file = b.path("src/root.zig"), .target = b.graph.host, .optimize = .debug });
    const generated_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/templates/generated_test.zig"),
            .target = b.graph.host,
            .optimize = .debug,
            .imports = &.{
                .{ .name = "zg_gui", .module = test_gui },
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
}

pub const FragmentContext = enum { flow, dl, ul, ol, thead, tbody, tfoot, tr, select, optgroup };

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
