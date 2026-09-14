const std = @import("std");
const html_tokenizer = @import("html-tokenizer");

pub const Span = html_tokenizer.Span;
pub const Attr = html_tokenizer.Tokenizer.Attr;

pub const Directive = enum {
    @"if",
    loop,
    @"else",
    text,
    html,
};

pub const Expression = struct {
    span: Span,
    kind: Kind,

    pub const Kind = union(enum) {
        directive: Directive,
        dynamic_attribute,
    };
};

pub fn directive(name: []const u8) ?Directive {
    if (name.len < 2 or name[0] != ':') return null;
    return std.meta.stringToEnum(Directive, name[1..]);
}

/// Returns the Scripty expression carried by an attribute, if any.
/// Directive values are expressions except for `:else`, which takes no value.
/// Ordinary attribute values are expressions when they start with `$`.
pub fn embeddedExpression(attr: Attr, source: []const u8) ?Expression {
    const value = attr.value orelse return null;
    if (directive(attr.name.slice(source))) |kind| {
        if (kind == .@"else") return null;
        return .{ .span = value.span, .kind = .{ .directive = kind } };
    }
    if (std.mem.startsWith(u8, value.span.slice(source), "$")) {
        return .{ .span = value.span, .kind = .dynamic_attribute };
    }
    return null;
}

test "recognizes SuperHTML expression attributes" {
    const source = "<div :if=\"$show\" :else title=\"$title\" class=\"plain\">";
    var tokenizer: html_tokenizer.Tokenizer = .{
        .language = .superhtml,
        .return_attrs = true,
    };

    var found: usize = 0;
    while (tokenizer.next(source)) |token| switch (token) {
        .attr => |attr| {
            const expression = embeddedExpression(attr, source) orelse continue;
            found += 1;
            try std.testing.expect(expression.span.len() > 0);
        },
        else => {},
    };
    try std.testing.expectEqual(@as(usize, 2), found);
}
