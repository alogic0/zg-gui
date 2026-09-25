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
