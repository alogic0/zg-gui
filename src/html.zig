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
