//! Zig-owned UI projections and a browser-applied DOM command stream.
pub const html = @import("html.zig");
pub const patch = @import("patch.zig");
pub const Projection = @import("projection.zig").Projection;

test {
    _ = html;
    _ = patch;
    _ = @import("projection.zig");
}
