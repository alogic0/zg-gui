//! Generates src/font_metrics_data.zig from an OpenType / TrueType font.
//! Adapted from TrueType reader logic.
const std = @import("std");

pub const Reader = struct {
    bytes: []const u8,

    pub const Error = error{ EndOfStream, InvalidFontData };

    pub fn span(self: Reader, offset: usize, length: usize) Error![]const u8 {
        if (offset > self.bytes.len or length > self.bytes.len - offset) return error.EndOfStream;
        return self.bytes[offset..][0..length];
    }

    pub fn read(self: Reader, comptime T: type, offset: usize) Error!T {
        const width = @bitSizeOf(T) / 8;
        const b = try self.span(offset, width);
        return std.mem.readInt(T, b[0..width], .big);
    }
};

pub const TableId = enum { cmap, head, hhea, hmtx, maxp };

pub const Directory = struct {
    bytes: []const u8,
    cmap_offset: u32 = 0,
    cmap_length: u32 = 0,
    head_offset: u32 = 0,
    head_length: u32 = 0,
    hhea_offset: u32 = 0,
    hhea_length: u32 = 0,
    hmtx_offset: u32 = 0,
    hmtx_length: u32 = 0,
    maxp_offset: u32 = 0,
    maxp_length: u32 = 0,

    pub fn init(bytes: []const u8) !Directory {
        const r = Reader{ .bytes = bytes };
        const num_tables = try r.read(u16, 4);
        var dir = Directory{ .bytes = bytes };
        var offset: usize = 12;
        var i: usize = 0;
        while (i < num_tables) : (i += 1) {
            const tag = try r.span(offset, 4);
            const table_offset = try r.read(u32, offset + 8);
            const table_length = try r.read(u32, offset + 12);
            offset += 16;

            if (std.mem.eql(u8, tag, "cmap")) {
                dir.cmap_offset = table_offset;
                dir.cmap_length = table_length;
            } else if (std.mem.eql(u8, tag, "head")) {
                dir.head_offset = table_offset;
                dir.head_length = table_length;
            } else if (std.mem.eql(u8, tag, "hhea")) {
                dir.hhea_offset = table_offset;
                dir.hhea_length = table_length;
            } else if (std.mem.eql(u8, tag, "hmtx")) {
                dir.hmtx_offset = table_offset;
                dir.hmtx_length = table_length;
            } else if (std.mem.eql(u8, tag, "maxp")) {
                dir.maxp_offset = table_offset;
                dir.maxp_length = table_length;
            }
        }
        if (dir.cmap_offset == 0 or dir.head_offset == 0 or dir.hhea_offset == 0 or dir.hmtx_offset == 0) {
            return error.InvalidFontData;
        }
        return dir;
    }
};

pub const FontMetrics = struct {
    units_per_em: u16,
    ascent: i16,
    descent: i16,
    line_gap: i16,
    num_glyphs: u16,
    num_h_metrics: u16,
    cmap_subtable_offset: u32,
    cmap_format: u16,
    bytes: []const u8,
    dir: Directory,

    pub fn load(bytes: []const u8) !FontMetrics {
        const dir = try Directory.init(bytes);
        const head = Reader{ .bytes = bytes[dir.head_offset..][0..dir.head_length] };
        const hhea = Reader{ .bytes = bytes[dir.hhea_offset..][0..dir.hhea_length] };
        const maxp = Reader{ .bytes = bytes[dir.maxp_offset..][0..dir.maxp_length] };
        const cmap = Reader{ .bytes = bytes[dir.cmap_offset..][0..dir.cmap_length] };

        const units_per_em = try head.read(u16, 18);
        const ascent = try hhea.read(i16, 4);
        const descent = try hhea.read(i16, 6);
        const line_gap = try hhea.read(i16, 8);
        const num_h_metrics = try hhea.read(u16, 34);
        const num_glyphs = try maxp.read(u16, 4);

        // Find Unicode cmap subtable (Platform 3/Encoding 1 or 10, or Platform 0)
        const num_subtables = try cmap.read(u16, 2);
        var subtable_offset: u32 = 0;
        var subtable_format: u16 = 0;
        var i: usize = 0;
        while (i < num_subtables) : (i += 1) {
            const platform_id = try cmap.read(u16, 4 + i * 8);
            const encoding_id = try cmap.read(u16, 4 + i * 8 + 2);
            const sub_offset = try cmap.read(u32, 4 + i * 8 + 4);
            const format = try cmap.read(u16, sub_offset);

            if ((platform_id == 3 and (encoding_id == 1 or encoding_id == 10)) or platform_id == 0) {
                if (format == 4 or format == 12) {
                    subtable_offset = sub_offset;
                    subtable_format = format;
                    if (format == 12) break; // Prefer format 12 for full Unicode
                }
            }
        }
        if (subtable_offset == 0) return error.NoSupportedCmap;

        return .{
            .units_per_em = units_per_em,
            .ascent = ascent,
            .descent = descent,
            .line_gap = line_gap,
            .num_glyphs = num_glyphs,
            .num_h_metrics = num_h_metrics,
            .cmap_subtable_offset = subtable_offset,
            .cmap_format = subtable_format,
            .bytes = bytes,
            .dir = dir,
        };
    }

    pub fn glyphIndex(self: FontMetrics, codepoint: u21) u16 {
        const cmap = Reader{ .bytes = self.bytes[self.dir.cmap_offset..][0..self.dir.cmap_length] };
        if (self.cmap_format == 4) {
            if (codepoint > 0xFFFF) return 0;
            const sub = self.cmap_subtable_offset;
            const seg_count = (cmap.read(u16, sub + 6) catch return 0) / 2;
            const end_count_offset = sub + 14;
            const start_count_offset = end_count_offset + seg_count * 2 + 2;
            const id_delta_offset = start_count_offset + seg_count * 2;
            const id_range_offset = id_delta_offset + seg_count * 2;

            var i: usize = 0;
            while (i < seg_count) : (i += 1) {
                const end_code = cmap.read(u16, end_count_offset + i * 2) catch return 0;
                if (end_code >= codepoint) {
                    const start_code = cmap.read(u16, start_count_offset + i * 2) catch return 0;
                    if (start_code > codepoint) return 0;
                    const delta = cmap.read(i16, id_delta_offset + i * 2) catch return 0;
                    const range_off = cmap.read(u16, id_range_offset + i * 2) catch return 0;
                    if (range_off == 0) {
                        return @intCast((@as(i32, codepoint) + delta) & 0xFFFF);
                    } else {
                        const glyph_offset = id_range_offset + i * 2 + range_off + (codepoint - start_code) * 2;
                        const glyph_id = cmap.read(u16, glyph_offset) catch return 0;
                        if (glyph_id == 0) return 0;
                        return @intCast((@as(i32, glyph_id) + delta) & 0xFFFF);
                    }
                }
            }
        } else if (self.cmap_format == 12) {
            const sub = self.cmap_subtable_offset;
            const num_groups = cmap.read(u32, sub + 12) catch return 0;
            var i: usize = 0;
            while (i < num_groups) : (i += 1) {
                const group_offset = sub + 16 + i * 12;
                const start_char = cmap.read(u32, group_offset) catch return 0;
                const end_char = cmap.read(u32, group_offset + 4) catch return 0;
                const start_glyph = cmap.read(u32, group_offset + 8) catch return 0;
                if (codepoint >= start_char and codepoint <= end_char) {
                    return @intCast(start_glyph + (codepoint - start_char));
                }
            }
        }
        return 0;
    }

    pub fn advanceWidth(self: FontMetrics, glyph: u16) u16 {
        const hmtx = Reader{ .bytes = self.bytes[self.dir.hmtx_offset..][0..self.dir.hmtx_length] };
        if (glyph < self.num_h_metrics) {
            return hmtx.read(u16, @as(usize, glyph) * 4) catch 0;
        }
        // If glyph is beyond num_h_metrics, its advance width is the last one in the array
        if (self.num_h_metrics > 0) {
            return hmtx.read(u16, @as(usize, self.num_h_metrics - 1) * 4) catch 0;
        }
        return 0;
    }

    pub fn codepointAdvance(self: FontMetrics, codepoint: u21) u16 {
        const glyph = self.glyphIndex(codepoint);
        if (glyph == 0) return 0;
        return self.advanceWidth(glyph);
    }
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // Default font path
    var font_path: []const u8 = "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf";
    if (args.len > 1) {
        font_path = args[1];
    }

    const font_bytes = std.Io.Dir.cwd().readFileAlloc(
        init.io,
        font_path,
        arena,
        .limited(16 * 1024 * 1024),
    ) catch |err| {
        std.log.err("Failed to read font '{s}': {s}", .{ font_path, @errorName(err) });
        return err;
    };

    const font = try FontMetrics.load(font_bytes);

    // Normalize metrics to 1000 units_per_em for standard em-relative computation
    const scale: f32 = 1000.0 / @as(f32, @floatFromInt(font.units_per_em));
    const norm_ascent: i16 = @intFromFloat(@as(f32, @floatFromInt(font.ascent)) * scale);
    const norm_descent: i16 = @intFromFloat(@as(f32, @floatFromInt(font.descent)) * scale);
    const norm_line_gap: i16 = @intFromFloat(@as(f32, @floatFromInt(font.line_gap)) * scale);

    const out_path = "src/font_metrics_data.zig";
    const file = try std.Io.Dir.cwd().createFile(init.io, out_path, .{ .truncate = true });
    defer file.close(init.io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(init.io, &buffer);
    const w = &writer.interface;

    try w.print(
        \\//! Generated by tools/gen_diagram_font_metrics.zig.
        \\//! Source font: {s}
        \\//! Normalized to 1000 units per em.
        \\//! Do not edit by hand.
        \\
        \\pub const units_per_em: u16 = 1000;
        \\pub const ascent: i16 = {d};
        \\pub const descent: i16 = {d};
        \\pub const line_gap: i16 = {d};
        \\
        \\/// ASCII printable characters (0x20..=0x7E, count 95).
        \\pub const ascii_advances = [_]u16{{
        \\
    , .{ font_path, norm_ascent, norm_descent, norm_line_gap });

    // ASCII 0x20..=0x7E
    var cp: u21 = 0x20;
    while (cp <= 0x7E) : (cp += 1) {
        const raw_adv = font.codepointAdvance(cp);
        const norm_adv: u16 = @intFromFloat(@as(f32, @floatFromInt(raw_adv)) * scale);
        try w.print("    {d}, // '{c}' (0x{X:0>2})\n", .{ norm_adv, if (cp >= 0x20 and cp <= 0x7E) @as(u8, @intCast(cp)) else '?', cp });
    }

    try w.writeAll(
        \\};
        \\
        \\/// Latin-1 Supplement characters (0xA0..=0xFF, count 96).
        \\pub const latin1_advances = [_]u16{
        \\
    );

    // Latin-1 Supplement 0xA0..=0xFF
    cp = 0xA0;
    while (cp <= 0xFF) : (cp += 1) {
        const raw_adv = font.codepointAdvance(cp);
        const norm_adv: u16 = @intFromFloat(@as(f32, @floatFromInt(raw_adv)) * scale);
        try w.print("    {d}, // 0x{X:0>2}\n", .{ norm_adv, cp });
    }

    try w.writeAll(
        \\};
        \\
        \\/// Default advance width when a codepoint is unmapped (approximately average char width).
        \\pub const default_advance: u16 = 550;
        \\
        \\/// Full-width advance for CJK ideographs.
        \\pub const cjk_advance: u16 = 1000;
        \\
        \\/// Standard advance for Emoji glyphs.
        \\pub const emoji_advance: u16 = 1000;
        \\
    );

    try writer.interface.flush();
    std.log.info("Successfully generated {s} from {s}", .{ out_path, font_path });
}
