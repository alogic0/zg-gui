//! Headless font metrics and text measurement for diagram labels.
const std = @import("std");
pub const data = @import("font_metrics_data.zig");

pub const Line = struct {
    text: []const u8,
    width: f32,
};

pub const TextLayout = struct {
    lines: []const Line,
    width: f32,
    height: f32,
};

pub const Font = struct {
    font_size: f32,
    scale: f32,

    pub fn init(font_size: f32) Font {
        const safe_size = if (font_size <= 0 or !std.math.isFinite(font_size)) 14.0 else font_size;
        return .{
            .font_size = safe_size,
            .scale = safe_size / @as(f32, @floatFromInt(data.units_per_em)),
        };
    }

    /// Returns the horizontal advance width for a single Unicode codepoint in pixels.
    pub fn codepointAdvance(self: Font, cp: u21) f32 {
        const raw: f32 = blk: {
            if (cp >= 0x20 and cp <= 0x7E) {
                break :blk @floatFromInt(data.ascii_advances[cp - 0x20]);
            }
            if (cp >= 0xA0 and cp <= 0xFF) {
                break :blk @floatFromInt(data.latin1_advances[cp - 0xA0]);
            }
            // Tab character advances to ~4 spaces
            if (cp == '\t') {
                break :blk @as(f32, @floatFromInt(data.ascii_advances[0])) * 4.0;
            }
            // CJK Unified Ideographs, Hiragana, Katakana, Hangul, CJK Symbols
            if ((cp >= 0x4E00 and cp <= 0x9FFF) or
                (cp >= 0x3400 and cp <= 0x4DBF) or
                (cp >= 0x20000 and cp <= 0x2A6DF) or
                (cp >= 0x3000 and cp <= 0x303F) or
                (cp >= 0x3040 and cp <= 0x309F) or
                (cp >= 0x30A0 and cp <= 0x30FF) or
                (cp >= 0xAC00 and cp <= 0xD7AF))
            {
                break :blk @floatFromInt(data.cjk_advance);
            }
            // Emojis and miscellaneous symbols
            if ((cp >= 0x1F300 and cp <= 0x1F9FF) or
                (cp >= 0x2600 and cp <= 0x27BF))
            {
                break :blk @floatFromInt(data.emoji_advance);
            }
            break :blk @floatFromInt(data.default_advance);
        };
        return raw * self.scale;
    }

    /// Measures the total single-line width of a UTF-8 string.
    pub fn stringWidth(self: Font, text: []const u8) f32 {
        var total: f32 = 0;
        var it = (std.unicode.Utf8View.init(text) catch return @as(f32, @floatFromInt(text.len)) * self.codepointAdvance(' ')).iterator();
        while (it.nextCodepoint()) |cp| {
            total += self.codepointAdvance(cp);
        }
        return total;
    }

    /// Returns the recommended line height in pixels.
    pub fn lineHeight(self: Font) f32 {
        const raw = @as(f32, @floatFromInt(data.ascent - data.descent + data.line_gap));
        return raw * self.scale;
    }

    /// Returns the vertical distance from line top to text baseline in pixels.
    pub fn baselineOffset(self: Font) f32 {
        return @as(f32, @floatFromInt(data.ascent)) * self.scale;
    }

    /// Wraps text to fit within max_width. Respects explicit newlines and '<br>' breaks.
    pub fn wrapText(self: Font, allocator: std.mem.Allocator, text: []const u8, max_width: f32) !TextLayout {
        if (text.len == 0) {
            return .{
                .lines = &.{},
                .width = 0,
                .height = 0,
            };
        }

        var lines = std.ArrayList(Line).empty;
        errdefer lines.deinit(allocator);

        // Normalize explicit breaks: split by \n or <br> / <br/>
        var iter = ExplicitBreakIterator{ .source = text };
        var max_line_width: f32 = 0;

        while (iter.next()) |paragraph| {
            if (max_width <= 0 or self.stringWidth(paragraph) <= max_width) {
                const w = self.stringWidth(paragraph);
                if (w > max_line_width) max_line_width = w;
                try lines.append(allocator, .{ .text = paragraph, .width = w });
                continue;
            }

            // Word wrap paragraph
            var word_iter = std.mem.tokenizeScalar(u8, paragraph, ' ');
            var line_start: usize = 0;
            var current_line_len: usize = 0;
            var current_line_width: f32 = 0;
            const space_width = self.codepointAdvance(' ');

            while (word_iter.next()) |word| {
                const word_width = self.stringWidth(word);
                const word_start = @intFromPtr(word.ptr) - @intFromPtr(paragraph.ptr);

                if (current_line_len == 0) {
                    line_start = word_start;
                    current_line_len = word.len;
                    current_line_width = word_width;
                } else if (current_line_width + space_width + word_width <= max_width) {
                    current_line_len = (word_start + word.len) - line_start;
                    current_line_width += space_width + word_width;
                } else {
                    // Commit current line
                    const line_text = paragraph[line_start .. line_start + current_line_len];
                    if (current_line_width > max_line_width) max_line_width = current_line_width;
                    try lines.append(allocator, .{ .text = line_text, .width = current_line_width });

                    // Start new line with word
                    line_start = word_start;
                    current_line_len = word.len;
                    current_line_width = word_width;
                }
            }

            if (current_line_len > 0) {
                const line_text = paragraph[line_start .. line_start + current_line_len];
                if (current_line_width > max_line_width) max_line_width = current_line_width;
                try lines.append(allocator, .{ .text = line_text, .width = current_line_width });
            }
        }

        const total_height = @as(f32, @floatFromInt(lines.items.len)) * self.lineHeight();
        return .{
            .lines = try lines.toOwnedSlice(allocator),
            .width = max_line_width,
            .height = total_height,
        };
    }
};

const ExplicitBreakIterator = struct {
    source: []const u8,
    index: usize = 0,

    fn next(self: *ExplicitBreakIterator) ?[]const u8 {
        if (self.index >= self.source.len) return null;
        const remaining = self.source[self.index..];

        var i: usize = 0;
        while (i < remaining.len) : (i += 1) {
            if (remaining[i] == '\n') {
                const segment = remaining[0..i];
                self.index += i + 1;
                return segment;
            }
            if (std.mem.startsWith(u8, remaining[i..], "<br>")) {
                const segment = remaining[0..i];
                self.index += i + 4;
                return segment;
            }
            if (std.mem.startsWith(u8, remaining[i..], "<br/>")) {
                const segment = remaining[0..i];
                self.index += i + 5;
                return segment;
            }
            if (std.mem.startsWith(u8, remaining[i..], "<br />")) {
                const segment = remaining[0..i];
                self.index += i + 6;
                return segment;
            }
        }

        const segment = remaining;
        self.index = self.source.len;
        return segment;
    }
};

test "font advance widths and line height calculation" {
    const font = Font.init(14.0);
    const space_w = font.codepointAdvance(' ');
    const char_a_w = font.codepointAdvance('A');
    try std.testing.expect(space_w > 0);
    try std.testing.expect(char_a_w > space_w);

    const text_w = font.stringWidth("Hello, World!");
    try std.testing.expect(text_w > 50.0 and text_w < 120.0);

    const line_h = font.lineHeight();
    try std.testing.expect(line_h > 14.0 and line_h < 22.0);
}

test "cjk and emoji advance fallback" {
    const font = Font.init(16.0);
    const cjk_w = font.codepointAdvance(0x4E16); // '世'
    const emoji_w = font.codepointAdvance(0x1F600); // 😀
    try std.testing.expectEqual(16.0, cjk_w);
    try std.testing.expectEqual(16.0, emoji_w);
}

test "text wrapping and break iterator" {
    const font = Font.init(14.0);
    const text = "First line<br>Second long sentence that should be wrapped into multiple lines";
    const layout = try font.wrapText(std.testing.allocator, text, 150.0);
    defer std.testing.allocator.free(layout.lines);

    try std.testing.expect(layout.lines.len >= 3);
    try std.testing.expectEqualStrings("First line", layout.lines[0].text);
    try std.testing.expect(layout.width <= 150.0);
    try std.testing.expect(layout.height > 40.0);
}
