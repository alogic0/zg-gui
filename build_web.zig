const std = @import("std");

pub const Features = struct { browser: bool = false, math: bool = false, prepaint: bool = false, files: bool = false };

pub fn addWebApp(b: *std.Build, input: struct {
    dependency: *std.Build.Dependency,
    artifact: *std.Build.Step.Compile,
    features: Features = .{},
}) void {
    const target = input.artifact.root_module.resolved_target.?.result;
    if (target.cpu.arch != .wasm32 or target.os.tag != .freestanding)
        @panic("addWebApp requires a freestanding wasm32 artifact");
    const declaration = .{
        .version = 1,
        .wasm = b.fmt("./{s}.wasm", .{input.artifact.name}),
        .browser = input.features.browser,
        .math = input.features.math,
    };
    const manifest = if (input.features.files)
        std.json.Stringify.valueAlloc(b.allocator, .{ .version = 2, .wasm = declaration.wasm, .browser = declaration.browser, .math = declaration.math, .files = true }, .{}) catch @panic("OOM")
    else
        std.json.Stringify.valueAlloc(b.allocator, declaration, .{}) catch @panic("OOM");
    const file = b.addWriteFiles().add("app.json", manifest);
    b.getInstallStep().dependOn(&b.addInstallFile(file, "web/app.json").step);
    b.getInstallStep().dependOn(&b.addInstallFile(input.artifact.getEmittedBin(), b.fmt("web/{s}.wasm", .{input.artifact.name})).step);
    for ([_][]const u8{ "runtime.js", "dom.js", "node-registry.js", "local-datetime.js", "startup.js", "auto-start.js" }) |name| {
        b.getInstallStep().dependOn(&b.addInstallFile(input.dependency.path(b.fmt("web/{s}", .{name})), b.fmt("web/gui/{s}", .{name})).step);
    }
    inline for (.{ "browser", "math", "prepaint" }) |feature| {
        if (@field(input.features, feature)) {
            const name = comptime if (std.mem.eql(u8, feature, "prepaint")) "prepaint.js" else feature ++ "-host.js";
            b.getInstallStep().dependOn(&b.addInstallFile(input.dependency.path("web/" ++ name), "web/gui/" ++ name).step);
        }
    }
    if (input.features.files) b.getInstallStep().dependOn(&b.addInstallFile(input.dependency.path("web/file-host.js"), "web/gui/file-host.js").step);
}
