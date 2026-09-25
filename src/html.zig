const std = @import("std");

pub const Writer = struct {
    buffer: []u8,
    len: usize = 0,
    failed: bool = false,

    pub noinline fn add(self: *Writer, value: []const u8) void {
        if (self.failed) return;
        if (self.len + value.len > self.buffer.len) {
            self.failed = true;
            return;
        }
        @memcpy(self.buffer[self.len .. self.len + value.len], value);
        self.len += value.len;
    }

    pub noinline fn escaped(self: *Writer, value: []const u8) void {
        var start: usize = 0;
        for (value, 0..) |byte, i| {
            const escaped_value: []const u8 = switch (byte) {
                '&' => "&amp;",
                '<' => "&lt;",
                '>' => "&gt;",
                '"' => "&quot;",
                '\'' => "&#39;",
                else => continue,
            };
            self.add(value[start..i]);
            self.add(escaped_value);
            start = i + 1;
        }
        self.add(value[start..]);
    }

    pub fn print(self: *Writer, comptime format: []const u8, args: anytype) void {
        if (self.failed) return;
        const written = std.fmt.bufPrint(self.buffer[self.len..], format, args) catch {
            self.failed = true;
            return;
        };
        self.len += written.len;
    }

    pub noinline fn int(self: *Writer, value: anytype) void {
        if (self.failed) return;
        var buf: [40]u8 = undefined;
        const str = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
            self.failed = true;
            return;
        };
        self.add(str);
    }

    pub noinline fn intDelimited(self: *Writer, value: anytype, delimiter: u8) void {
        if (self.failed) return;
        const T = @TypeOf(value);
        const info = @typeInfo(T);
        switch (info) {
            .int, .comptime_int => {},
            else => @compileError("intDelimited requires an integer type"),
        }
        if (value == 0) {
            self.add("0");
            return;
        }

        var buf: [64]u8 = undefined;
        var idx: usize = buf.len;
        var count: usize = 0;
        var v: u128 = undefined;
        var negative = false;

        const is_signed = switch (info) {
            .int => |int_info| int_info.signedness == .signed,
            .comptime_int => value < 0,
            else => false,
        };

        if (is_signed and value < 0) {
            negative = true;
            v = @as(u128, @abs(value));
        } else {
            v = @as(u128, @intCast(value));
        }

        while (v > 0) : (count += 1) {
            if (count > 0 and count % 3 == 0) {
                idx -= 1;
                buf[idx] = delimiter;
            }
            idx -= 1;
            buf[idx] = @as(u8, @intCast(v % 10)) + '0';
            v /= 10;
        }

        if (negative) {
            idx -= 1;
            buf[idx] = '-';
        }

        self.add(buf[idx..]);
    }

    pub inline fn intCommas(self: *Writer, value: anytype) void {
        self.intDelimited(value, ',');
    }

    pub noinline fn attribute(self: *Writer, name: []const u8, value: []const u8) void {
        self.add(" ");
        self.add(name);
        self.add("=\"");
        self.escaped(value);
        self.add("\"");
    }

    pub noinline fn booleanAttribute(self: *Writer, name: []const u8, present: bool) void {
        if (present) {
            self.add(" ");
            self.add(name);
        }
    }

    pub const Stream = struct {
        parent: *Writer,
        writer: std.Io.Writer,

        pub fn finish(self: *Stream) void {
            if (self.parent.failed) return;
            self.parent.len += self.writer.end;
        }
    };

    pub fn openStream(self: *Writer) Stream {
        if (self.failed or self.len >= self.buffer.len) {
            return .{
                .parent = self,
                .writer = std.Io.Writer.fixed(&.{}),
            };
        }
        return .{
            .parent = self,
            .writer = std.Io.Writer.fixed(self.buffer[self.len..]),
        };
    }

    pub fn writeStream(self: *Writer, comptime action: anytype, args: anytype) void {
        if (self.failed or self.len >= self.buffer.len) {
            self.failed = true;
            return;
        }
        var w = std.Io.Writer.fixed(self.buffer[self.len..]);
        @call(.auto, action, .{&w} ++ args) catch {
            self.failed = true;
            return;
        };
        self.len += w.end;
    }

    pub noinline fn option(self: *Writer, value: []const u8, label: []const u8, selected: bool) void {
        self.add("<option");
        self.attribute("value", value);
        self.booleanAttribute("selected", selected);
        self.add(">");
        self.escaped(label);
        self.add("</option>");
    }

    pub noinline fn time(self: *Writer, datetime: []const u8, label: []const u8) void {
        self.add("<time");
        self.attribute("datetime", datetime);
        self.add(">");
        self.escaped(label);
        self.add("</time>");
    }

    pub noinline fn tag(self: *Writer, element: []const u8, content: []const u8) void {
        self.add("<");
        self.add(element);
        self.add(">");
        self.escaped(content);
        self.add("</");
        self.add(element);
        self.add(">");
    }

    pub noinline fn formatBytes(self: *Writer, bytes: u64) void {
        if (self.failed) return;
        if (bytes < 1024) {
            self.print("{d} B", .{bytes});
            return;
        }

        const units = [_][]const u8{ "KB", "MB", "GB", "TB", "PB" };
        var unit_idx: usize = 0;
        var divisor: u64 = 1024;

        while (unit_idx + 1 < units.len and bytes >= divisor * 1024) {
            divisor *= 1024;
            unit_idx += 1;
        }

        var whole = bytes / divisor;
        const remainder = bytes % divisor;
        var tenth = (remainder * 10 + (divisor / 2)) / divisor;
        if (tenth >= 10) {
            whole += 1;
            tenth = 0;
        }

        self.print("{d}.{d} {s}", .{ whole, tenth, units[unit_idx] });
    }

    pub noinline fn formatDuration(self: *Writer, ms: u64) void {
        if (self.failed) return;
        if (ms < 1000) {
            self.print("{d}ms", .{ms});
            return;
        }
        if (ms < 60_000) {
            const whole = ms / 1000;
            const remainder = ms % 1000;
            const tenth = (remainder * 10 + 500) / 1000;
            if (tenth >= 10) {
                self.print("{d}.0s", .{whole + 1});
                return;
            }
            self.print("{d}.{d}s", .{ whole, tenth });
            return;
        }
        if (ms < 3600_000) {
            const mins = ms / 60_000;
            const secs = (ms % 60_000) / 1000;
            if (secs == 0) {
                self.print("{d}m", .{mins});
                return;
            }
            self.print("{d}m {d}s", .{ mins, secs });
            return;
        }
        const hours = ms / 3600_000;
        const mins = (ms % 3600_000) / 60_000;
        if (mins == 0) {
            self.print("{d}h", .{hours});
            return;
        }
        self.print("{d}h {d}m", .{ hours, mins });
    }

    pub fn slice(self: *const Writer) []const u8 {
        return self.buffer[0..self.len];
    }
};

test "writer escapes markup-sensitive text" {
    var buffer: [128]u8 = undefined;
    var writer = Writer{ .buffer = &buffer };
    writer.escaped("<Morgan & 'Reed'>");
    try std.testing.expectEqualStrings("&lt;Morgan &amp; &#39;Reed&#39;&gt;", writer.slice());
}

test "writer batches literal text without changing escaping or overflow admission" {
    var bytes: [64]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };
    writer.escaped("Plain Unicode 🧭 and <tag> & \"quote\"");
    try std.testing.expectEqualStrings("Plain Unicode 🧭 and &lt;tag&gt; &amp; &quot;quote&quot;", writer.slice());
    var small: [4]u8 = undefined;
    writer = .{ .buffer = &small };
    writer.escaped("<");
    try std.testing.expectEqualStrings("&lt;", writer.slice());
    writer.escaped("&");
    try std.testing.expect(writer.failed);
    try std.testing.expectEqualStrings("&lt;", writer.slice());
}

test "writer formats integers and delimited numbers without allocation" {
    var bytes: [128]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };

    writer.int(0);
    writer.add(" ");
    writer.int(42);
    writer.add(" ");
    writer.int(-99);
    try std.testing.expectEqualStrings("0 42 -99", writer.slice());

    writer.len = 0;
    writer.intCommas(0);
    writer.add(" ");
    writer.intCommas(999);
    writer.add(" ");
    writer.intCommas(1000);
    writer.add(" ");
    writer.intCommas(29669);
    writer.add(" ");
    writer.intCommas(947481);
    writer.add(" ");
    writer.intCommas(-1234567);
    try std.testing.expectEqualStrings("0 999 1,000 29,669 947,481 -1,234,567", writer.slice());

    writer.len = 0;
    writer.intDelimited(1234567890, '_');
    try std.testing.expectEqualStrings("1_234_567_890", writer.slice());

    writer.len = 0;
    writer.intCommas(std.math.minInt(i64));
    try std.testing.expectEqualStrings("-9,223,372,036,854,775,808", writer.slice());

    writer.len = 0;
    writer.intCommas(std.math.maxInt(u64));
    try std.testing.expectEqualStrings("18,446,744,073,709,551,615", writer.slice());

    const rt_i64: i64 = -29669;
    writer.len = 0;
    writer.intCommas(rt_i64);
    try std.testing.expectEqualStrings("-29,669", writer.slice());

    const rt_u64: u64 = 29669;
    writer.len = 0;
    writer.intCommas(rt_u64);
    try std.testing.expectEqualStrings("29,669", writer.slice());

    // Buffer overflow preserves failure flag
    var small: [5]u8 = undefined;
    var small_writer = Writer{ .buffer = &small };
    small_writer.intCommas(1000000); // "1,000,000" needs 9 bytes
    try std.testing.expect(small_writer.failed);
    try std.testing.expectEqualStrings("", small_writer.slice());
}

test "writer attributes and boolean attributes escape properly" {
    var bytes: [128]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };

    writer.add("<button");
    writer.attribute("data-label", "Save & Continue");
    writer.booleanAttribute("disabled", true);
    writer.booleanAttribute("hidden", false);
    writer.add(">Submit</button>");

    try std.testing.expectEqualStrings("<button data-label=\"Save &amp; Continue\" disabled>Submit</button>", writer.slice());
}

test "writer streaming adaptors write directly to buffer" {
    var bytes: [128]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };

    var s = writer.openStream();
    try s.writer.print("Value: {d}, Hex: 0x{x}", .{ 42, 255 });
    s.finish();
    try std.testing.expectEqualStrings("Value: 42, Hex: 0xff", writer.slice());

    const helper = struct {
        fn writeFormatted(w: *std.Io.Writer, label: []const u8, val: i32) !void {
            try w.print(" | {s}={d}", .{ label, val });
        }
    }.writeFormatted;

    writer.writeStream(helper, .{ "delta", -15 });
    try std.testing.expectEqualStrings("Value: 42, Hex: 0xff | delta=-15", writer.slice());

    // Stream overflow sets failed flag
    var small: [8]u8 = undefined;
    var small_writer = Writer{ .buffer = &small };
    var small_stream = small_writer.openStream();
    try std.testing.expectError(error.WriteFailed, small_stream.writer.writeAll("long string that exceeds buffer"));
}

test "writer form elements and semantic tags escape safely" {
    var bytes: [256]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };

    writer.option("yesterday", "Since yesterday", true);
    writer.option("month", "Last 30 <days>", false);
    try std.testing.expectEqualStrings("<option value=\"yesterday\" selected>Since yesterday</option><option value=\"month\">Last 30 &lt;days&gt;</option>", writer.slice());

    writer.len = 0;
    writer.time("2026-09-25T03:00:00Z", "Sept 25, 2026");
    try std.testing.expectEqualStrings("<time datetime=\"2026-09-25T03:00:00Z\">Sept 25, 2026</time>", writer.slice());

    writer.len = 0;
    writer.tag("strong", "Alert & Warning");
    try std.testing.expectEqualStrings("<strong>Alert &amp; Warning</strong>", writer.slice());
}

test "writer formats byte sizes without allocation" {
    var bytes: [128]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };

    writer.formatBytes(0);
    writer.add(" ");
    writer.formatBytes(1023);
    writer.add(" ");
    writer.formatBytes(1024);
    writer.add(" ");
    writer.formatBytes(1536);
    writer.add(" ");
    writer.formatBytes(29481000);
    writer.add(" ");
    writer.formatBytes(1024 * 1024 * 1024);
    writer.add(" ");
    writer.formatBytes(2638827906662);

    try std.testing.expectEqualStrings("0 B 1023 B 1.0 KB 1.5 KB 28.1 MB 1.0 GB 2.4 TB", writer.slice());
}

test "writer formats durations without allocation" {
    var bytes: [128]u8 = undefined;
    var writer = Writer{ .buffer = &bytes };

    writer.formatDuration(0);
    writer.add(" ");
    writer.formatDuration(45);
    writer.add(" ");
    writer.formatDuration(999);
    writer.add(" ");
    writer.formatDuration(1000);
    writer.add(" ");
    writer.formatDuration(1500);
    writer.add(" ");
    writer.formatDuration(59940);
    writer.add(" ");
    writer.formatDuration(120_000);
    writer.add(" ");
    writer.formatDuration(135_000);
    writer.add(" ");
    writer.formatDuration(3600_000);
    writer.add(" ");
    writer.formatDuration(5400_000);

    try std.testing.expectEqualStrings("0ms 45ms 999ms 1.0s 1.5s 59.9s 2m 2m 15s 1h 1h 30m", writer.slice());
}

