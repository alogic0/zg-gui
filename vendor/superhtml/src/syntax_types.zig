const std = @import("std");

pub const Language = enum {
    html,
    superhtml,
    xml,

    /// Use to map file extensions to a Language, supports aliases.
    pub fn fromSliceResilient(s: []const u8) ?Language {
        const Alias = enum { html, superhtml, shtml, xml };

        const alias = std.meta.stringToEnum(Alias, s) orelse return null;
        return switch (alias) {
            .superhtml, .shtml => .superhtml,
            .html => .html,
            .xml => .xml,
        };
    }
};

pub const max_size = 4 * 1024 * 1024 * 1024;

pub const Range = struct {
    start: Pos,
    end: Pos,

    const Pos = struct {
        row: u32,
        col: u32,
    };
};

pub const Line = struct { line: []const u8, start: u32 };

pub const Span = struct {
    start: u32,
    end: u32,

    pub fn len(span: Span) u32 {
        return span.end - span.start;
    }

    pub fn slice(self: Span, src: []const u8) []const u8 {
        return src[self.start..self.end];
    }

    pub fn range(self: Span, code: []const u8) Range {
        var selection: Range = .{
            .start = .{ .row = 0, .col = 0 },
            .end = undefined,
        };

        for (code[0..self.start]) |c| {
            if (c == '\n') {
                selection.start.row += 1;
                selection.start.col = 0;
            } else selection.start.col += 1;
        }

        selection.end = selection.start;
        for (code[self.start..self.end]) |c| {
            if (c == '\n') {
                selection.end.row += 1;
                selection.end.col = 0;
            } else selection.end.col += 1;
        }
        return selection;
    }

    /// Finds the line around a node. Choose simple nodes if you don't want
    /// unwanted newlines in the middle.
    pub fn line(span: Span, src: []const u8) Line {
        var idx = span.start;
        const s = while (idx > 0) : (idx -= 1) {
            if (src[idx] == '\n') break idx + 1;
        } else 0;

        idx = span.end;
        const e = while (idx < src.len) : (idx += 1) {
            if (src[idx] == '\n') break idx;
        } else src.len - 1;

        return .{ .line = src[s..e], .start = s };
    }

    /// Returns the tag name inside a span containing an HTML start or end tag.
    pub fn getName(span: Span, src: []const u8, _: Language) Span {
        var idx: u32 = span.start;
        if (idx >= span.end or src[idx] != '<') return .{ .start = idx, .end = idx };
        idx += 1;
        if (idx < span.end and src[idx] == '/') idx += 1;

        const start = idx;
        while (idx < span.end) : (idx += 1) {
            switch (src[idx]) {
                '\t', '\n', '\r', 0x0c, ' ', '/', '>' => break,
                else => continue,
            }
            break;
        }
        return .{ .start = start, .end = idx };
    }

    pub fn debug(span: Span, src: []const u8) void {
        std.debug.print("{s}", .{span.slice(src)});
    }
};

test "tag names are available without importing the full HTML module" {
    const source = "<section class=x></section>";
    try std.testing.expectEqualStrings(
        "section",
        (Span{ .start = 0, .end = 17 }).getName(source, .html).slice(source),
    );
    try std.testing.expectEqualStrings(
        "section",
        (Span{ .start = 17, .end = source.len }).getName(source, .html).slice(source),
    );
}
