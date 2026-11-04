//! Opt-in adapter for a caller-selected math_typesetter public module.
const std = @import("std");
const provider = @import("math_typesetter");

pub const Options = provider.Options;
pub const Diagnostic = provider.Diagnostic;
pub const Update = union(enum) { changed, unchanged, diagnostic: Diagnostic };
pub const Error = std.mem.Allocator.Error || error{ OutputLimit, RevisionOverflow };

/// Owns copied source and accepted serialized MathML. Views borrow until a
/// successful update or deinit. Failed updates leave every accepted field intact.
pub const Formula = struct {
    allocator: std.mem.Allocator,
    output_limit: usize,
    source: []const u8 = "",
    output: []const u8 = "",
    options: Options = .{},
    revision: u64 = 0,

    pub fn init(input: struct { allocator: std.mem.Allocator, output_limit: usize = 64 * 1024 }) Formula {
        return .{ .allocator = input.allocator, .output_limit = input.output_limit };
    }

    pub fn matches(self: Formula, input: struct { source: []const u8, options: Options = .{} }) bool {
        return self.revision != 0 and std.mem.eql(u8, self.source, input.source) and std.meta.eql(self.options, input.options);
    }

    pub fn update(self: *Formula, input: struct { source: []const u8, options: Options = .{} }) Error!Update {
        if (self.matches(.{ .source = input.source, .options = input.options })) return .unchanged;
        if (self.revision == std.math.maxInt(u64)) return error.RevisionOverflow;
        var rendered = try provider.renderMathMlAlloc(self.allocator, input.source, input.options);
        errdefer rendered.deinit(self.allocator);
        switch (rendered) {
            .diagnostic => |failure| return .{ .diagnostic = failure },
            .output => |output| {
                if (output.len > self.output_limit) return error.OutputLimit;
                const source = try self.allocator.dupe(u8, input.source);
                // Nothing below can fail; ownership transfers only on admission.
                if (self.revision != 0) {
                    self.allocator.free(self.source);
                    self.allocator.free(self.output);
                }
                self.source = source;
                self.output = output;
                self.options = input.options;
                self.revision += 1;
                return .changed;
            },
        }
    }

    /// Releases owned bytes and resets to an empty reusable formula.
    pub fn deinit(self: *Formula) void {
        if (self.revision != 0) {
            self.allocator.free(self.source);
            self.allocator.free(self.output);
        }
        self.* = init(.{ .allocator = self.allocator, .output_limit = self.output_limit });
    }
};

test "formula caches exact source/options and preserves output on rejected updates" {
    var formula = Formula.init(.{ .allocator = std.testing.allocator, .output_limit = 512 });
    defer formula.deinit();
    try std.testing.expectEqual(Update.changed, try formula.update(.{ .source = "x_1" }));
    const first = formula.output;
    try std.testing.expectEqual(Update.unchanged, try formula.update(.{ .source = "x_1" }));
    try std.testing.expect(first.ptr == formula.output.ptr);
    try std.testing.expectEqual(@as(u64, 1), formula.revision);
    const rejected = try formula.update(.{ .source = "\\unsupported" });
    try std.testing.expect(rejected == .diagnostic);
    try std.testing.expectEqualStrings("x_1", formula.source);
    try std.testing.expect(first.ptr == formula.output.ptr);
    try std.testing.expectEqual(Update.changed, try formula.update(.{ .source = "x_1", .options = .{ .display_mode = .display_math } }));
    try std.testing.expectEqual(@as(u64, 2), formula.revision);
    formula.output_limit = 1;
    try std.testing.expectError(error.OutputLimit, formula.update(.{ .source = "y" }));
    try std.testing.expectEqualStrings("x_1", formula.source);
    formula.revision = std.math.maxInt(u64);
    try std.testing.expectError(error.RevisionOverflow, formula.update(.{ .source = "z" }));
}

fn allocationProbe(allocator: std.mem.Allocator) !void {
    var formula = Formula.init(.{ .allocator = allocator });
    defer formula.deinit();
    _ = try formula.update(.{ .source = "a" });
    const accepted = formula.output;
    _ = formula.update(.{ .source = "b" }) catch |err| {
        try std.testing.expectEqualStrings("a", formula.source);
        try std.testing.expect(accepted.ptr == formula.output.ptr);
        try std.testing.expectEqual(@as(u64, 1), formula.revision);
        return err;
    };
}
test "allocation failure at every update allocation keeps accepted ownership" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
