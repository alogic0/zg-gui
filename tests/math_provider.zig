//! Synthetic public-provider fixture for adapter ownership and failure checks.
const std = @import("std");
pub const Options = struct { display_mode: enum { inline_math, display_math } = .inline_math };
pub const Diagnostic = struct { code: enum { unknown_command } = .unknown_command };
pub const RenderResult = union(enum) {
    output: []u8,
    diagnostic: Diagnostic,
    pub fn deinit(self: *RenderResult, allocator: std.mem.Allocator) void {
        if (self.* == .output) allocator.free(self.output);
    }
};
pub fn renderMathMlAlloc(allocator: std.mem.Allocator, source: []const u8, options: Options) std.mem.Allocator.Error!RenderResult {
    if (std.mem.indexOfScalar(u8, source, '\\') != null) return .{ .diagnostic = .{} };
    return .{ .output = try std.fmt.allocPrint(allocator, "<math class=\"zig-math\" display=\"{s}\"><mi>{s}</mi></math>", .{ if (options.display_mode == .display_math) "block" else "inline", source }) };
}
