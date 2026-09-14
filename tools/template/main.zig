const std = @import("std");
const compiler = @import("compiler.zig");

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.next();
    const source_path = args.next() orelse return error.MissingTemplatePath;
    const output_path = args.next() orelse return error.MissingOutputPath;
    if (args.next() != null) return error.UnexpectedArgument;
    const allocator = init.arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, source_path, allocator, .limited(compiler.max_source_bytes));
    var diagnostic = compiler.Diagnostic{};
    const code = compiler.compile(allocator, .{ .source = source, .name = source_path, .diagnostic = &diagnostic }) catch |err| {
        if (err == error.InvalidTemplate) {
            const before = source[0..@min(source.len, diagnostic.offset)];
            const line = std.mem.count(u8, before, "\n") + 1;
            const column = before.len - (if (std.mem.lastIndexOfScalar(u8, before, '\n')) |i| i + 1 else 0) + 1;
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ source_path, line, column, diagnostic.message });
            std.process.exit(1);
        }
        return err;
    };
    // No output is opened until parsing, validation and generation succeed.
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = code });
}
