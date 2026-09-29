//! GUI template formatter/beautifier.
//! Parses .gui.html templates using the vendored SuperHTML tokenizer and
//! formats them with consistent indentation, tag balancing, and clean structure.

const std = @import("std");
const html = @import("html-tokenizer");
const Allocator = std.mem.Allocator;

pub const Diagnostic = struct {
    offset: usize = 0,
    name: []const u8 = "",
    line: usize = 1,
    column: usize = 1,
    message: []const u8 = "",

    pub fn set(d: *Diagnostic, name: []const u8, source: []const u8, offset: usize, message: []const u8) void {
        const off = @min(offset, source.len);
        const before = source[0..off];
        d.offset = off;
        d.name = name;
        d.line = std.mem.count(u8, before, "\n") + 1;
        const last_nl = std.mem.lastIndexOfScalar(u8, before, '\n');
        d.column = if (last_nl) |idx| before.len - idx else before.len + 1;
        d.message = message;
    }
};

pub const FormatOptions = struct {
    indent_size: u32 = 2,
    max_line_width: u32 = 120,
    diagnostic: ?*Diagnostic = null,
    file_name: []const u8 = "<template>",
};

pub const Error = error{
    OutOfMemory,
    InvalidTemplate,
};

pub const Node = struct {
    kind: Kind,

    pub const Kind = union(enum) {
        element: Element,
        text: []const u8,
        comment: []const u8,
    };
};

pub const Element = struct {
    tag_name: []const u8,
    attrs: []const []const u8,
    is_void: bool,
    is_self_closing: bool,
    children: []const Node,
    has_preceding_blank_line: bool = false,
};

fn isPhrasing(name: []const u8) bool {
    const list = "span a strong em small time b i code br label input textarea button output meter progress img select svg";
    var it = std.mem.splitScalar(u8, list, ' ');
    while (it.next()) |item| {
        if (std.ascii.eqlIgnoreCase(name, item)) return true;
    }
    return false;
}

fn isAlwaysBlock(name: []const u8) bool {
    const list = "div section article header footer nav aside main table thead tbody tfoot tr ul ol dl dt dd form fieldset details template";
    var it = std.mem.splitScalar(u8, list, ' ');
    while (it.next()) |item| {
        if (std.ascii.eqlIgnoreCase(name, item)) return true;
    }
    return false;
}

fn isVerbatimContainer(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "textarea") or std.ascii.eqlIgnoreCase(name, "pre");
}

fn normalizeWhitespace(a: Allocator, trimmed: []const u8, leading_space: bool, trailing_space: bool) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(a);
    if (leading_space) try out.append(a, ' ');
    var in_ws = false;
    for (trimmed) |c| {
        if (std.ascii.isWhitespace(c)) {
            if (!in_ws) {
                try out.append(a, ' ');
                in_ws = true;
            }
        } else {
            try out.append(a, c);
            in_ws = false;
        }
    }
    if (trailing_space and (out.items.len == 0 or out.items[out.items.len - 1] != ' ')) {
        try out.append(a, ' ');
    }
    return out.toOwnedSlice(a);
}

const BuilderElement = struct {
    tag_name: []const u8,
    attrs: std.ArrayList([]const u8),
    content_start: u32 = 0,
    is_void: bool,
    is_self_closing: bool,
    children: std.ArrayList(Node),
    has_preceding_blank_line: bool = false,
};

pub fn parse(allocator: Allocator, source: []const u8, options: FormatOptions) Error![]const Node {
    var tokenizer = html.Tokenizer{ .language = .html };
    var stack: std.ArrayList(BuilderElement) = .empty;
    defer {
        for (stack.items) |*b| {
            b.attrs.deinit(allocator);
            b.children.deinit(allocator);
        }
        stack.deinit(allocator);
    }
    var roots: std.ArrayList(Node) = .empty;
    errdefer roots.deinit(allocator);

    var prev_end: u32 = 0;

    while (tokenizer.next(source)) |token| switch (token) {
        .parse_error => {
            if (options.diagnostic) |d| {
                d.set(options.file_name, source, tokenizer.idx, "syntax error in template");
            }
            return error.InvalidTemplate;
        },
        .doctype => {
            prev_end = @max(prev_end, tokenizer.idx);
        },
        .comment => |span| {
            const comment_text = span.slice(source);
            const node = Node{ .kind = .{ .comment = comment_text } };
            if (stack.items.len > 0) {
                try stack.items[stack.items.len - 1].children.append(allocator, node);
            } else {
                try roots.append(allocator, node);
            }
            prev_end = span.end;
        },
        .tag => |tag| {
            const tag_name = tag.name.slice(source);
            const between = if (tag.span.start >= prev_end) source[prev_end..tag.span.start] else "";
            const has_blank = std.mem.count(u8, between, "\n") >= 2;

            switch (tag.kind) {
                .end, .end_self => {
                    if (stack.items.len == 0) {
                        if (options.diagnostic) |d| {
                            d.set(options.file_name, source, tag.span.start, "unexpected closing tag");
                        }
                        return error.InvalidTemplate;
                    }
                    var builder = stack.pop().?;
                    defer {
                        builder.attrs.deinit(allocator);
                        builder.children.deinit(allocator);
                    }
                    if (!std.ascii.eqlIgnoreCase(builder.tag_name, tag_name)) {
                        if (options.diagnostic) |d| {
                            d.set(options.file_name, source, tag.span.start, "mismatched closing tag");
                        }
                        return error.InvalidTemplate;
                    }

                    const children: []const Node = if (isVerbatimContainer(builder.tag_name)) blk: {
                        const verbatim_raw = source[builder.content_start..tag.span.start];
                        var vlist = std.ArrayList(Node).empty;
                        try vlist.append(allocator, Node{ .kind = .{ .text = verbatim_raw } });
                        break :blk try vlist.toOwnedSlice(allocator);
                    } else try builder.children.toOwnedSlice(allocator);

                    const elem = Element{
                        .tag_name = builder.tag_name,
                        .attrs = try builder.attrs.toOwnedSlice(allocator),
                        .is_void = false,
                        .is_self_closing = false,
                        .children = children,
                        .has_preceding_blank_line = builder.has_preceding_blank_line,
                    };
                    const node = Node{ .kind = .{ .element = elem } };
                    if (stack.items.len > 0) {
                        try stack.items[stack.items.len - 1].children.append(allocator, node);
                    } else {
                        try roots.append(allocator, node);
                    }
                },
                .start, .start_self => {
                    var attrs: std.ArrayList([]const u8) = .empty;
                    errdefer attrs.deinit(allocator);

                    var attr_scanner = html.Tokenizer{
                        .language = .html,
                        .return_attrs = true,
                        .idx = tag.span.start,
                    };
                    while (attr_scanner.next(source[0..tag.span.end])) |part| switch (part) {
                        .attr => |a| {
                            try attrs.append(allocator, a.span().slice(source));
                        },
                        else => {},
                    };

                    const is_void = tag.isVoid(source, .html);
                    const is_self = tag.kind == .start_self;

                    if (is_void or is_self) {
                        const elem = Element{
                            .tag_name = tag_name,
                            .attrs = try attrs.toOwnedSlice(allocator),
                            .is_void = is_void,
                            .is_self_closing = is_self,
                            .children = &.{},
                            .has_preceding_blank_line = has_blank,
                        };
                        const node = Node{ .kind = .{ .element = elem } };
                        if (stack.items.len > 0) {
                            try stack.items[stack.items.len - 1].children.append(allocator, node);
                        } else {
                            try roots.append(allocator, node);
                        }
                    } else {
                        try stack.append(allocator, .{
                            .tag_name = tag_name,
                            .attrs = attrs,
                            .content_start = tag.span.end,
                            .is_void = false,
                            .is_self_closing = false,
                            .children = .empty,
                            .has_preceding_blank_line = has_blank,
                        });
                        if (std.ascii.eqlIgnoreCase(tag_name, "textarea")) {
                            tokenizer.gotoRcData("textarea");
                        }
                    }
                },
            }
            prev_end = tag.span.end;
        },
        .text => |span| {
            const raw = span.slice(source);
            var in_verbatim = false;
            for (stack.items) |item| {
                if (isVerbatimContainer(item.tag_name)) {
                    in_verbatim = true;
                    break;
                }
            }

            if (in_verbatim) {
                const node = Node{ .kind = .{ .text = raw } };
                if (stack.items.len > 0) {
                    try stack.items[stack.items.len - 1].children.append(allocator, node);
                } else {
                    try roots.append(allocator, node);
                }
            } else {
                const trimmed = std.mem.trim(u8, raw, " \t\r\n");
                if (trimmed.len > 0) {
                    const is_first_child = (stack.items.len == 0 or stack.items[stack.items.len - 1].children.items.len == 0);
                    const parent_is_phrasing = if (stack.items.len > 0) isPhrasing(stack.items[stack.items.len - 1].tag_name) else false;

                    const raw_has_leading = std.ascii.isWhitespace(raw[0]) or (span.start > 0 and std.ascii.isWhitespace(source[span.start - 1]));
                    const raw_has_trailing = std.ascii.isWhitespace(raw[raw.len - 1]) or (span.end < source.len and std.ascii.isWhitespace(source[span.end]));

                    const has_leading = if (is_first_child and !parent_is_phrasing) false else raw_has_leading;
                    const has_trailing = raw_has_trailing;

                    const norm = try normalizeWhitespace(allocator, trimmed, has_leading, has_trailing);
                    const node = Node{ .kind = .{ .text = norm } };
                    if (stack.items.len > 0) {
                        try stack.items[stack.items.len - 1].children.append(allocator, node);
                    } else {
                        try roots.append(allocator, node);
                    }
                } else {
                    if (stack.items.len > 0) {
                        const parent = stack.items[stack.items.len - 1].tag_name;
                        if (isPhrasing(parent) and stack.items[stack.items.len - 1].children.items.len > 0) {
                            const last_child = stack.items[stack.items.len - 1].children.items[stack.items[stack.items.len - 1].children.items.len - 1];
                            const already_ends_with_space = switch (last_child.kind) {
                                .text => |t| t.len > 0 and t[t.len - 1] == ' ',
                                else => false,
                            };
                            if (!already_ends_with_space) {
                                try stack.items[stack.items.len - 1].children.append(allocator, Node{ .kind = .{ .text = " " } });
                            }
                        }
                    }
                }
            }
            prev_end = span.end;
        },
        else => {},
    };

    if (stack.items.len > 0) {
        if (options.diagnostic) |d| {
            const top = stack.items[stack.items.len - 1];
            d.set(options.file_name, source, top.content_start, "unclosed tag at end of template");
        }
        return error.InvalidTemplate;
    }
    return roots.toOwnedSlice(allocator);
}

fn calculateInlineLength(node: Node) ?usize {
    switch (node.kind) {
        .text => |t| {
            if (std.mem.indexOfScalar(u8, t, '\n') != null) return null;
            return t.len;
        },
        .comment => |c| {
            if (std.mem.indexOfScalar(u8, c, '\n') != null) return null;
            return c.len;
        },
        .element => |elem| {
            if (isAlwaysBlock(elem.tag_name) and elem.children.len > 0) return null;
            if (isVerbatimContainer(elem.tag_name) and elem.children.len > 0) return null;

            var len: usize = 1 + elem.tag_name.len;
            for (elem.attrs) |attr| len += 1 + attr.len;
            if (elem.is_self_closing) {
                len += 3; // " />"
                return len;
            } else {
                len += 1; // ">"
            }
            if (elem.is_void) return len;

            for (elem.children) |child| {
                const child_len = calculateInlineLength(child) orelse return null;
                len += child_len;
            }

            len += 3 + elem.tag_name.len; // "</tag>"
            return len;
        },
    }
}

fn hasMixedPhrasing(elem: Element) bool {
    var has_text = false;
    var has_elem = false;
    for (elem.children) |child| {
        switch (child.kind) {
            .text => |t| {
                if (std.mem.trim(u8, t, " \t\r\n").len > 0) has_text = true;
            },
            .element => |e| {
                if (isPhrasing(e.tag_name)) has_elem = true;
            },
            .comment => {},
        }
    }
    return has_text and has_elem;
}

fn canInline(elem: Element, current_indent_chars: usize, max_line_width: u32) bool {
    if (elem.is_void) return true;
    if (elem.children.len == 0) return true;
    if (isAlwaysBlock(elem.tag_name)) return false;
    if (isVerbatimContainer(elem.tag_name)) return false;

    // Check if children contain any block elements
    for (elem.children) |child| {
        switch (child.kind) {
            .element => |c_elem| {
                if (isAlwaysBlock(c_elem.tag_name)) return false;
            },
            .text => |t| {
                if (std.mem.indexOfScalar(u8, t, '\n') != null) return false;
            },
            .comment => return false,
        }
    }

    // Preserve mixed phrasing elements inline to prevent corrupting text whitespace
    if (hasMixedPhrasing(elem)) return true;

    const node = Node{ .kind = .{ .element = elem } };
    const inline_len = calculateInlineLength(node) orelse return false;
    return current_indent_chars + inline_len <= max_line_width;
}

const Emitter = struct {
    allocator: Allocator,
    out: std.ArrayList(u8),
    options: FormatOptions,

    fn writeIndent(self: *Emitter, depth: u32) Error!void {
        const total = depth * self.options.indent_size;
        try self.out.appendNTimes(self.allocator, ' ', total);
    }

    fn emitInline(self: *Emitter, node: Node) Error!void {
        switch (node.kind) {
            .text => |t| try self.out.appendSlice(self.allocator, t),
            .comment => |c| try self.out.appendSlice(self.allocator, c),
            .element => |elem| {
                try self.out.append(self.allocator, '<');
                try self.out.appendSlice(self.allocator, elem.tag_name);
                for (elem.attrs) |attr| {
                    try self.out.append(self.allocator, ' ');
                    try self.out.appendSlice(self.allocator, attr);
                }
                if (elem.is_self_closing) {
                    try self.out.appendSlice(self.allocator, " />");
                    return;
                }
                try self.out.append(self.allocator, '>');
                if (elem.is_void) return;

                for (elem.children) |child| {
                    try self.emitInline(child);
                }

                try self.out.appendSlice(self.allocator, "</");
                try self.out.appendSlice(self.allocator, elem.tag_name);
                try self.out.append(self.allocator, '>');
            },
        }
    }

    fn emitNode(self: *Emitter, node: Node, depth: u32) Error!void {
        switch (node.kind) {
            .text => |t| {
                const trimmed = std.mem.trim(u8, t, " \t\r\n");
                if (trimmed.len > 0) {
                    try self.writeIndent(depth);
                    try self.out.appendSlice(self.allocator, trimmed);
                    try self.out.append(self.allocator, '\n');
                }
            },
            .comment => |c| {
                try self.writeIndent(depth);
                try self.out.appendSlice(self.allocator, c);
                try self.out.append(self.allocator, '\n');
            },
            .element => |elem| {
                if (elem.has_preceding_blank_line and self.out.items.len > 0 and self.out.items[self.out.items.len - 1] == '\n') {
                    if (self.out.items.len < 2 or self.out.items[self.out.items.len - 2] != '\n') {
                        try self.out.append(self.allocator, '\n');
                    }
                }

                const indent_chars = depth * self.options.indent_size;
                if (canInline(elem, indent_chars, self.options.max_line_width)) {
                    try self.writeIndent(depth);
                    try self.emitInline(node);
                    try self.out.append(self.allocator, '\n');
                    return;
                }

                // Verbatim element (<textarea>, <pre>)
                if (isVerbatimContainer(elem.tag_name)) {
                    try self.writeIndent(depth);
                    try self.out.append(self.allocator, '<');
                    try self.out.appendSlice(self.allocator, elem.tag_name);
                    for (elem.attrs) |attr| {
                        try self.out.append(self.allocator, ' ');
                        try self.out.appendSlice(self.allocator, attr);
                    }
                    try self.out.append(self.allocator, '>');
                    for (elem.children) |child| {
                        switch (child.kind) {
                            .text => |t| try self.out.appendSlice(self.allocator, t),
                            else => try self.emitInline(child),
                        }
                    }
                    try self.out.appendSlice(self.allocator, "</");
                    try self.out.appendSlice(self.allocator, elem.tag_name);
                    try self.out.appendSlice(self.allocator, ">\n");
                    return;
                }

                // Multiline element
                try self.writeIndent(depth);
                try self.out.append(self.allocator, '<');
                try self.out.appendSlice(self.allocator, elem.tag_name);
                for (elem.attrs) |attr| {
                    try self.out.append(self.allocator, ' ');
                    try self.out.appendSlice(self.allocator, attr);
                }
                if (elem.is_self_closing) {
                    try self.out.appendSlice(self.allocator, " />\n");
                    return;
                }
                try self.out.appendSlice(self.allocator, ">\n");
                if (elem.is_void) return;

                for (elem.children) |child| {
                    try self.emitNode(child, depth + 1);
                }

                try self.writeIndent(depth);
                try self.out.appendSlice(self.allocator, "</");
                try self.out.appendSlice(self.allocator, elem.tag_name);
                try self.out.appendSlice(self.allocator, ">\n");
            },
        }
    }
};

pub fn format(allocator: Allocator, source: []const u8, options: FormatOptions) Error![]u8 {
    if (options.diagnostic) |d| d.* = .{ .name = options.file_name };
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const roots = try parse(a, source, options);

    var emitter = Emitter{
        .allocator = allocator,
        .out = .empty,
        .options = options,
    };
    errdefer emitter.out.deinit(allocator);

    for (roots) |root| {
        try emitter.emitNode(root, 0);
    }

    return emitter.out.toOwnedSlice(allocator);
}

test "formatter: basic tags and indentation" {
    const a = std.testing.allocator;
    const input = "<div><p>Hello <span>world</span></p><input type=\"text\"></div>";
    const formatted = try format(a, input, .{});
    defer a.free(formatted);

    const expected =
        \\<div>
        \\  <p>Hello <span>world</span></p>
        \\  <input type="text">
        \\</div>
        \\
    ;
    try std.testing.expectEqualStrings(expected, formatted);
}

test "formatter: idempotent on already formatted template" {
    const a = std.testing.allocator;
    const template =
        \\<section class="card">
        \\  <div class="row">
        \\    <span>Title</span>
        \\    <button :ref="btn" :on-click="$action">Click</button>
        \\  </div>
        \\</section>
        \\
    ;
    const pass1 = try format(a, template, .{});
    defer a.free(pass1);
    try std.testing.expectEqualStrings(template, pass1);

    const pass2 = try format(a, pass1, .{});
    defer a.free(pass2);
    try std.testing.expectEqualStrings(pass1, pass2);
}

const compiler = @import("compiler.zig");

test "formatter: formatted templates compile identically to minified" {
    const a = std.testing.allocator;
    const input = "<section class=\"card\"><div class=\"field-row\"><span>First Name</span><button class=\"contact-field-value\" type=\"button\" :ref=\"first_edit\" :on-click=\"$edit_action\" data-value=\"0\" :visible=\"$first_reading\" aria-disabled=\"$editing_disabled\"><strong :ref=\"first\" :text=\"$first\"></strong></button><input :ref=\"first_editor\" aria-label=\"Edit First Name\" :visible=\"$first_editing\" :value=\"$first_value\" disabled=\"$editing_disabled\" :input=\"$edit_input\" data-input-prefix=\"0:\" type=\"text\"></div></section>";

    var d1 = compiler.Diagnostic{};
    const code1 = try compiler.compile(a, .{ .source = input, .name = "test.gui.html", .diagnostic = &d1 });
    defer a.free(code1);

    const formatted = try format(a, input, .{});
    defer a.free(formatted);

    const pass2 = try format(a, formatted, .{});
    defer a.free(pass2);
    try std.testing.expectEqualStrings(formatted, pass2);

    var d2 = compiler.Diagnostic{};
    const code2 = try compiler.compile(a, .{ .source = formatted, .name = "test.gui.html", .diagnostic = &d2 });
    defer a.free(code2);

    // Node count and ref mappings match
    try std.testing.expect(std.mem.indexOf(u8, code2, ".@\"first_edit\" = try space.node(4)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code2, ".@\"first\" = try space.node(5)") != null);
    try std.testing.expect(std.mem.indexOf(u8, code2, ".@\"first_editor\" = try space.node(6)") != null);
}

test "formatter: textarea verbatim and comments" {
    const a = std.testing.allocator;
    const input =
        \\<div>
        \\  <!-- Section comment -->
        \\  <textarea id="notes" rows="5">
        \\Line 1
        \\  Line 2
        \\</textarea>
        \\</div>
        \\
    ;
    const formatted = try format(a, input, .{});
    defer a.free(formatted);
    try std.testing.expectEqualStrings(input, formatted);
}

test "formatter: diagnostics on syntax error and mismatched tags" {
    const a = std.testing.allocator;
    var d = Diagnostic{};

    const bad_mismatch = "<div><span>hello</div></span>";
    const res1 = format(a, bad_mismatch, .{ .diagnostic = &d, .file_name = "test.gui.html" });
    try std.testing.expectError(error.InvalidTemplate, res1);
    try std.testing.expectEqualStrings("test.gui.html", d.name);
    try std.testing.expectEqualStrings("mismatched closing tag", d.message);
    try std.testing.expectEqual(@as(usize, 1), d.line);

    const bad_unclosed = "<section><div><span>text</span>";
    const res2 = format(a, bad_unclosed, .{ .diagnostic = &d, .file_name = "unclosed.gui.html" });
    try std.testing.expectError(error.InvalidTemplate, res2);
    try std.testing.expectEqualStrings("unclosed.gui.html", d.name);
    try std.testing.expectEqualStrings("unclosed tag at end of template", d.message);
}



