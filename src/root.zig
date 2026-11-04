//! Zig-owned UI projections and a browser-applied DOM command stream.
pub const html = @import("html.zig");
pub const patch = @import("patch.zig");
pub const browser = @import("browser.zig");
pub const Projection = @import("projection.zig").Projection;
pub const StaticRenderer = @import("projection.zig").StaticRenderer;
pub const renderHtml = @import("projection.zig").renderHtml;
pub const renderHtmlWithNodes = @import("projection.zig").renderHtmlWithNodes;
pub const template = @import("template.zig");
pub const namespace = @import("namespace.zig");
pub const snapshot = @import("snapshot.zig");
pub const compact_key = @import("compact_key.zig");
pub const CompactKeyRegistry = compact_key.CompactKeyRegistry;
pub const StringCompactKeys = compact_key.StringCompactKeys;
pub const charts = @import("charts.zig");
pub const window = @import("window.zig");
pub const Window = window.Window;

test {
    _ = html;
    _ = patch;
    _ = browser;
    _ = @import("projection.zig");
    _ = template;
    _ = snapshot;
    _ = namespace;
    _ = compact_key;
    _ = window;
    _ = charts;
}
