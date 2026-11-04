const std = @import("std");
const math = @import("zg_math");
pub export fn check() u32 {
    var formula = math.Formula.init(.{ .allocator = std.heap.wasm_allocator, .output_limit = 512 });
    defer formula.deinit();
    _ = formula.update(.{ .source = "x_1" }) catch return 0;
    return @intCast(formula.output.len);
}
