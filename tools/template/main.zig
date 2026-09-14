const std = @import("std");
const compiler = @import("compiler.zig");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const source_path = args.next() orelse return error.MissingTemplatePath;
    const output_path = args.next() orelse return error.MissingOutputPath;
    const allocator = init.arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, source_path, allocator, .limited(compiler.max_source_bytes));
    var components: std.ArrayList(compiler.Component) = .empty;
    while (args.next()) |name| {
        const path = args.next() orelse return error.MissingComponentPath;
        if (components.items.len == 64) return error.TooManyComponents;
        const contents = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(compiler.max_source_bytes));
        try components.append(allocator, .{ .name = name, .file = .{ .name = path, .source = contents } });
    }
    var diagnostic = compiler.Diagnostic{};
    const code = compiler.compile(allocator, .{ .source = source, .name = source_path, .diagnostic = &diagnostic, .components = components.items }) catch |err| {
        if (err == error.InvalidTemplate) {
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ diagnostic.name, diagnostic.line, diagnostic.column, diagnostic.message });
            std.process.exit(1);
        }
        return err;
    };
    // No output is opened until parsing, validation and generation succeed.
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = code });
}
