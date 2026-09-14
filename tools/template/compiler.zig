//! Native template compiler. No tokenizer or source text is linked into WASM.
const std = @import("std");
const html = @import("html-tokenizer");
const syntax = @import("template-syntax");
const Allocator = std.mem.Allocator;
const Attr = html.Tokenizer.Attr;
const Error = error{ OutOfMemory, InvalidTemplate };
pub const max_source_bytes = 256 * 1024;
pub const Diagnostic = struct { offset: usize = 0, message: []const u8 = "" };
pub const Input = struct {
    source: []const u8,
    name: []const u8,
    diagnostic: *Diagnostic,
};

const Node = struct {
    tag: html.Tokenizer.Token.Tag,
    attrs: []const Attr,
    children: std.ArrayList(usize) = .empty,
    close_start: usize,
    end: usize,
    slot: u32,
    loop_limit: ?usize = null,
    in_loop: bool = false,
    factor: usize = 1,
};
const Emission = struct { idx: usize, in_loop: bool, factor: usize };
const Code = struct {
    allocator: Allocator,
    bytes: std.ArrayList(u8) = .empty,
    fn add(c: *Code, value: []const u8) Error!void {
        if (c.bytes.items.len + value.len > 4 * 1024 * 1024) return error.InvalidTemplate;
        try c.bytes.appendSlice(c.allocator, value);
    }
    fn print(c: *Code, comptime format: []const u8, args: anytype) Error!void {
        try c.add(try std.fmt.allocPrint(c.allocator, format, args));
    }
    fn string(c: *Code, value: []const u8) Error!void {
        try c.add("\"");
        for (value) |byte| switch (byte) {
            '"' => try c.add("\\\""),
            '\\' => try c.add("\\\\"),
            '\n' => try c.add("\\n"),
            '\r' => try c.add("\\r"),
            '\t' => try c.add("\\t"),
            0...8, 11, 12, 14...31, 127 => try c.print("\\x{x:0>2}", .{byte}),
            else => try c.add(&.{byte}),
        };
        try c.add("\"");
    }
};

pub fn compile(allocator: Allocator, input: Input) Error![]u8 {
    input.diagnostic.* = .{};
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var compiler = Compiler{ .a = arena.allocator(), .input = input, .code = .{ .allocator = arena.allocator() } };
    if (input.source.len > max_source_bytes) return compiler.reject(0, "template exceeds 256 KiB");
    if (!std.unicode.utf8ValidateSlice(input.source)) return compiler.reject(0, "template must be valid UTF-8");
    try compiler.parse();
    for (compiler.roots.items) |idx| try compiler.validate(.{ .idx = idx, .in_loop = false });
    try compiler.generate();
    return allocator.dupe(u8, compiler.code.bytes.items);
}

const Compiler = struct {
    a: Allocator,
    input: Input,
    code: Code,
    nodes: std.ArrayList(Node) = .empty,
    roots: std.ArrayList(usize) = .empty,
    entries: usize = 0,

    fn reject(c: *Compiler, at: usize, message: []const u8) Error {
        c.input.diagnostic.* = .{ .offset = at, .message = message };
        return error.InvalidTemplate;
    }
    fn name(c: *const Compiler, idx: usize) []const u8 {
        return c.nodes.items[idx].tag.name.slice(c.input.source);
    }
    fn attr(c: *const Compiler, input: struct { idx: usize, name: []const u8 }) ?Attr {
        for (c.nodes.items[input.idx].attrs) |a| {
            if (std.mem.eql(u8, a.name.slice(c.input.source), input.name)) return a;
        }
        return null;
    }
    fn value(c: *Compiler, a: Attr) Error![]const u8 {
        const v = a.value orelse return c.reject(a.name.start, "directive requires a quoted value");
        if (v.quote == .none) return c.reject(v.span.start, "bindings must use quoted values");
        return v.span.slice(c.input.source);
    }

    fn parse(c: *Compiler) Error!void {
        var tokenizer = html.Tokenizer{ .language = .html };
        var stack: std.ArrayList(usize) = .empty;
        var attrs: std.ArrayList(Attr) = .empty;
        while (tokenizer.next(c.input.source)) |token| switch (token) {
            .parse_error => |e| return c.reject(e.span.start, @tagName(e.tag)),
            .doctype => |d| return c.reject(d.span.start, "templates are HTML fragments; put the doctype in the host page"),
            .tag => |tag| {
                // The attribute mode emits names instead of complete tags for
                // some token states. Keep structure and attribute scans separate.
                var attributes = html.Tokenizer{ .language = .html, .return_attrs = true, .idx = tag.span.start };
                while (attributes.next(c.input.source[0..tag.span.end])) |part| switch (part) {
                    .attr => |a| {
                        if (attrs.items.len == 64) return c.reject(a.name.start, "element exceeds 64 attributes");
                        try attrs.append(c.a, a);
                    },
                    .parse_error => |e| return c.reject(e.span.start, @tagName(e.tag)),
                    else => {},
                };
                const tag_name = tag.name.slice(c.input.source);
                switch (tag.kind) {
                    .end, .end_self => {
                        if (tag.kind == .end_self or attrs.items.len > 0) return c.reject(tag.span.start, "invalid closing tag");
                        if (stack.items.len == 0) return c.reject(tag.span.start, "closing tag has no opener");
                        const idx = stack.items[stack.items.len - 1];
                        if (!std.mem.eql(u8, tag_name, c.name(idx))) return c.reject(tag.span.start, "closing tag does not match its opener");
                        c.nodes.items[idx].close_start = tag.span.start;
                        c.nodes.items[idx].end = tag.span.end;
                        stack.items.len -= 1;
                    },
                    .start, .start_self => {
                        if (!oneOf(tag_name, "main header footer section article aside nav div p span h1 h2 h3 h4 h5 h6 a strong em small b i code pre br hr form fieldset legend label input textarea button output ul ol li img details summary")) {
                            return c.reject(tag.name.start, "unsupported element; use the documented HTML fragment subset");
                        }
                        if (tag.kind == .start_self and !tag.isVoid(c.input.source, .html)) return c.reject(tag.span.start, "non-void HTML elements require an explicit closing tag");
                        for (stack.items) |parent| {
                            const ancestor = c.name(parent);
                            if (oneOf(ancestor, "p h1 h2 h3 h4 h5 h6") and !isPhrasing(tag_name)) return c.reject(tag.name.start, "block content would implicitly close a phrasing-only ancestor");
                            if (oneOf(tag_name, "a button form") and std.mem.eql(u8, tag_name, ancestor)) return c.reject(tag.name.start, "nested interactive element would be repaired by the browser");
                            if (std.mem.eql(u8, ancestor, "button") and oneOf(tag_name, "a input textarea button")) return c.reject(tag.name.start, "interactive content is not allowed inside a button");
                        }
                        const parent_name = if (stack.items.len > 0) c.name(stack.items[stack.items.len - 1]) else "";
                        if (oneOf(parent_name, "ul ol") and !std.mem.eql(u8, tag_name, "li")) return c.reject(tag.name.start, "list containers require direct li children");
                        if (std.mem.eql(u8, tag_name, "li") and !oneOf(parent_name, "ul ol")) return c.reject(tag.name.start, "li requires a ul or ol parent");
                        if (stack.items.len == 64 or c.nodes.items.len == 4096) return c.reject(tag.span.start, "template exceeds depth 64 or 4096 elements");
                        const idx = c.nodes.items.len;
                        try c.nodes.append(c.a, .{
                            .tag = tag,
                            .attrs = try c.a.dupe(Attr, attrs.items),
                            .close_start = tag.span.end,
                            .end = tag.span.end,
                            .slot = @intCast(idx + 1),
                        });
                        if (stack.items.len > 0) try c.nodes.items[stack.items[stack.items.len - 1]].children.append(c.a, idx) else try c.roots.append(c.a, idx);
                        if (!tag.isVoid(c.input.source, .html)) try stack.append(c.a, idx);
                        if (std.mem.eql(u8, tag_name, "textarea")) tokenizer.gotoRcData("textarea");
                    },
                }
                attrs.clearRetainingCapacity();
            },
            else => {},
        };
        if (stack.items.len > 0) return c.reject(c.nodes.items[stack.items[stack.items.len - 1]].tag.span.start, "unclosed element");
        if (c.roots.items.len == 0) return c.reject(0, "template must contain an element");
    }

    fn binding(c: *Compiler, input: struct { attr: Attr, in_loop: bool }) Error!void {
        const v = try c.value(input.attr);
        if (v.len < 2 or v[0] != '$' or !validPath(v[1..])) return c.reject(input.attr.name.start, "expected $field.path; expressions belong in the Zig view");
        if ((std.mem.eql(u8, v, "$item") or std.mem.startsWith(u8, v, "$item.")) and !input.in_loop) return c.reject(input.attr.name.start, "$item is only available inside a loop");
    }

    fn validate(c: *Compiler, input: struct { idx: usize, in_loop: bool, factor: usize = 1 }) Error!void {
        const node = &c.nodes.items[input.idx];
        node.in_loop = input.in_loop;
        node.factor = input.factor;
        const tag_name = c.name(input.idx);
        const is_void = node.tag.isVoid(c.input.source, .html);
        var has_text = false;
        var has_value = false;
        var has_if = false;
        var has_visible = false;
        var has_loop = false;
        for (node.attrs, 0..) |a, i| {
            const n = a.name.slice(c.input.source);
            for (node.attrs[0..i]) |before| {
                if (std.ascii.eqlIgnoreCase(n, before.name.slice(c.input.source))) return c.reject(a.name.start, "duplicate attribute");
            }
            if (std.mem.eql(u8, n, ":ref")) {
                const ref = try c.value(a);
                if (!identifier(ref) or input.in_loop) return c.reject(a.name.start, ":ref requires a simple name outside loops");
                for (c.nodes.items[0..input.idx], 0..) |_, previous| {
                    if (c.attr(.{ .idx = previous, .name = ":ref" })) |other| {
                        if (std.mem.eql(u8, ref, try c.value(other))) return c.reject(a.name.start, "duplicate :ref");
                    }
                }
                continue;
            }
            if (std.mem.eql(u8, n, ":limit")) {
                const limit = std.fmt.parseInt(usize, try c.value(a), 10) catch return c.reject(a.name.start, ":limit requires an integer from 1 to 1024");
                if (limit == 0 or limit > 1024) return c.reject(a.name.start, ":limit requires an integer from 1 to 1024");
                node.loop_limit = limit;
                continue;
            }
            if (std.mem.eql(u8, n, ":key")) {
                if (!validPath(try c.value(a))) return c.reject(a.name.start, ":key requires an item field path");
                continue;
            }
            if (n.len > 0 and n[0] == ':') {
                // Reuse SuperHTML's directive recognition, but define GUI semantics here.
                if (syntax.directive(n)) |d| switch (d) {
                    .text => has_text = true,
                    .@"if" => has_if = true,
                    .loop => has_loop = true,
                    else => return c.reject(a.name.start, "this SuperHTML directive is not supported by GUI templates"),
                } else if (std.mem.eql(u8, n, ":value")) {
                    has_value = true;
                    if (!oneOf(tag_name, "input textarea")) return c.reject(a.name.start, ":value requires input or textarea");
                } else if (std.mem.eql(u8, n, ":visible")) {
                    has_visible = true;
                } else if (std.mem.eql(u8, n, ":checked")) {
                    const type_attr = c.attr(.{ .idx = input.idx, .name = "type" }) orelse return c.reject(a.name.start, ":checked requires a static checkbox or radio type");
                    if (!std.mem.eql(u8, tag_name, "input") or !oneOf(try c.value(type_attr), "checkbox radio")) return c.reject(a.name.start, ":checked requires a checkbox or radio");
                } else if (std.mem.eql(u8, n, ":input")) {
                    if (!oneOf(tag_name, "input textarea")) return c.reject(a.name.start, ":input requires input or textarea");
                } else if (!std.mem.eql(u8, n, ":on-click")) {
                    return c.reject(a.name.start, "unknown GUI directive");
                }
                try c.binding(.{ .attr = a, .in_loop = input.in_loop });
            } else {
                if (!attributeName(n) or std.mem.startsWith(u8, n, "on") or oneOf(n, "data-node-id data-event data-input-kind")) return c.reject(a.name.start, "reserved or unsupported attribute name");
                if (a.value) |v| if (std.mem.startsWith(u8, v.span.slice(c.input.source), "$")) {
                    if (!dynamicAttribute(n)) return c.reject(a.name.start, "unsupported dynamic attribute; use a property directive for form state");
                    try c.binding(.{ .attr = a, .in_loop = input.in_loop });
                };
            }
        }
        if (has_text and (is_void or has_value or has_if or has_loop or std.mem.eql(u8, tag_name, "textarea"))) return c.reject(node.tag.span.start, ":text conflicts with this element or its content owner");
        if ((has_text or (has_value and std.mem.eql(u8, tag_name, "textarea"))) and std.mem.trim(u8, c.input.source[node.tag.span.end..node.close_start], " \t\r\n").len > 0) return c.reject(node.tag.span.start, "text/value bindings require empty content");
        if ((has_if and (is_void or has_visible or has_value)) or (has_loop and (is_void or has_value))) return c.reject(node.tag.span.start, "conflicting structural or visibility directives");
        if (has_value and c.attr(.{ .idx = input.idx, .name = "value" }) != null) return c.reject(node.tag.span.start, ":value conflicts with value");
        if (has_value) if (c.attr(.{ .idx = input.idx, .name = "type" })) |a| {
            if (a.value != null and std.mem.eql(u8, a.value.?.span.slice(c.input.source), "file")) return c.reject(a.name.start, "file input values cannot be controlled by a template");
        };
        if (c.attr(.{ .idx = input.idx, .name = ":checked" }) != null and c.attr(.{ .idx = input.idx, .name = "checked" }) != null) return c.reject(node.tag.span.start, ":checked conflicts with checked");
        if ((has_visible or has_if) and c.attr(.{ .idx = input.idx, .name = "hidden" }) != null) return c.reject(node.tag.span.start, "visibility binding conflicts with hidden");
        if (c.attr(.{ .idx = input.idx, .name = ":input" }) != null) {
            if (c.attr(.{ .idx = input.idx, .name = "type" })) |a| {
                if (a.value != null and oneOf(a.value.?.span.slice(c.input.source), "checkbox radio") and c.attr(.{ .idx = input.idx, .name = "data-value-format" }) != null) return c.reject(a.name.start, "checkbox/radio input format is generated automatically");
            }
        }
        if (has_loop) {
            if (input.in_loop) return c.reject(node.tag.span.start, "nested loops are not supported");
            if (node.loop_limit == null or c.attr(.{ .idx = input.idx, .name = ":key" }) == null) return c.reject(node.tag.span.start, ":loop requires :key and :limit");
            if (node.children.items.len != 1) return c.reject(node.tag.span.start, "loop container requires exactly one child element");
            const child = c.nodes.items[node.children.items[0]];
            if (std.mem.trim(u8, c.input.source[node.tag.span.end..child.tag.span.start], " \t\r\n").len != 0 or std.mem.trim(u8, c.input.source[child.end..node.close_start], " \t\r\n").len != 0) return c.reject(node.tag.span.start, "loop container permits only whitespace around its child element");
        } else if (node.loop_limit != null or c.attr(.{ .idx = input.idx, .name = ":key" }) != null) return c.reject(node.tag.span.start, ":key and :limit require :loop");
        for (node.children.items) |child| try c.validate(.{ .idx = child, .in_loop = input.in_loop or has_loop, .factor = input.factor * (node.loop_limit orelse 1) });
    }

    fn literal(c: *Compiler, value_: []const u8) Error!void {
        if (value_.len == 0) return;
        try c.code.add("p.add(");
        try c.code.string(value_);
        try c.code.add(");\n");
    }
    fn expression(c: *Compiler, a: Attr) Error!void {
        const v = (try c.value(a))[1..];
        const item = std.mem.startsWith(u8, v, "item.");
        if (std.mem.eql(u8, v, "item")) {
            try c.code.add("item");
            return;
        }
        try c.code.print("binding.get({s}, ", .{if (item) "item" else "view"});
        try c.code.string(if (item) v[5..] else v);
        try c.code.add(", ");
        const range = a.name.range(c.input.source);
        try c.code.string(try std.fmt.allocPrint(c.a, "{s}:{d}:{d}", .{ c.input.name, range.start.row + 1, range.start.col + 1 }));
        try c.code.add(")");
    }
    fn id(c: *Compiler, input: struct { slot: u32, in_loop: bool }) Error!void {
        try c.code.add("(space.node(");
        if (input.in_loop) {
            try c.code.print("(binding.keyedId(.{{ .key = key, .slot = {d}, .stride = {d} }}) catch {{ p.html.failed = true; return; }})", .{ input.slot, c.nodes.items.len });
        } else try c.code.print("{d}", .{input.slot});
        try c.code.add(") catch { p.html.failed = true; return; })");
    }

    fn children(c: *Compiler, input: Emission) Error!void {
        const node = c.nodes.items[input.idx];
        if (node.loop_limit) |limit| {
            const loop = c.attr(.{ .idx = input.idx, .name = ":loop" }).?;
            const key = c.attr(.{ .idx = input.idx, .name = ":key" }).?;
            const child = node.children.items[0];
            c.entries += input.factor; // Order.
            try c.code.add("{\nconst items = ");
            try c.expression(loop);
            try c.code.print(";\nif (items.len > {d}) {{ p.html.failed = true; return; }}\nvar ids: [{d}]u32 = undefined;\nfor (items, 0..) |item, i| {{\nconst key: u32 = binding.get(item, ", .{ limit, limit });
            try c.code.string(try c.value(key));
            try c.code.add(", \"loop key\");\nids[i] = ");
            try c.id(.{ .slot = c.nodes.items[child].slot, .in_loop = true });
            try c.code.add(";\nfor (ids[0..i]) |previous| if (previous == ids[i]) { p.html.failed = true; return; };\n}\n");
            try c.code.print("p.keyedList(.{{ .owner = space.node({d}) catch unreachable, .nodes = ids[0..items.len] }});\nfor (items, 0..) |item, i| {{\nconst key: u32 = binding.get(item, ", .{node.slot});
            try c.code.string(try c.value(key));
            try c.code.print(", \"loop key\");\nconst child = p.beginChild(.{{ .owner = space.node({d}) catch unreachable, .node = ids[i] }});\n", .{node.slot});
            c.entries += limit * input.factor; // Parent identities.
            try c.code.print("element_{d}(p, view, item, key);\n", .{c.nodes.items[child].slot});
            try c.code.print("p.endChild(child);\n}}\np.order(.{{ .owner = space.node({d}) catch unreachable, .nodes = ids[0..items.len] }});\n}}\n", .{node.slot});
        } else {
            var previous: usize = node.tag.span.end;
            for (node.children.items) |child| {
                try c.literal(c.input.source[previous..c.nodes.items[child].tag.span.start]);
                try c.code.print("element_{d}(p, view{s});\n", .{ c.nodes.items[child].slot, if (input.in_loop) ", item, key" else "" });
                previous = c.nodes.items[child].end;
            }
            try c.literal(c.input.source[previous..node.close_start]);
        }
    }

    fn element(c: *Compiler, input: Emission) Error!void {
        const node = c.nodes.items[input.idx];
        const tag_name = c.name(input.idx);
        try c.code.print("fn element_{d}(p: anytype, view: anytype{s}) void {{\n_ = &view;\n{s}const node: u32 = ", .{ node.slot, if (input.in_loop) ", item: anytype, key: u32" else "", if (input.in_loop) "_ = &item;\n" else "" });
        try c.id(.{ .slot = node.slot, .in_loop = input.in_loop });
        try c.code.add(";\n");
        try c.literal(try std.fmt.allocPrint(c.a, "<{s}", .{tag_name}));
        try c.code.add("p.node(node);\n");
        const text_attr = c.attr(.{ .idx = input.idx, .name = ":text" });
        const value_attr = c.attr(.{ .idx = input.idx, .name = ":value" });
        const if_attr = c.attr(.{ .idx = input.idx, .name = ":if" });
        for (node.attrs) |a| {
            const n = a.name.slice(c.input.source);
            if (oneOf(n, ":ref :key :limit :loop :text :if")) continue;
            if (std.mem.eql(u8, n, ":value")) {
                if (std.mem.eql(u8, tag_name, "textarea")) continue;
                c.entries += input.factor;
                try c.code.add("p.formValue(.{ .node = node, .text_value = ");
                try c.expression(a);
                try c.code.add(" });\n");
            } else if (std.mem.eql(u8, n, ":checked") or std.mem.eql(u8, n, ":visible")) {
                c.entries += input.factor;
                try c.code.print("p.{s}(.{{ .node = node, .value = ", .{n[1..]});
                try c.expression(a);
                try c.code.add(" });\n");
            } else if (std.mem.eql(u8, n, ":on-click") or std.mem.eql(u8, n, ":input")) {
                c.entries += input.factor;
                try c.code.print("binding.event(p, \"{s}\", .{{ .node = node, .value = ", .{if (std.mem.eql(u8, n, ":input")) "data-input-kind" else "data-event"});
                try c.expression(a);
                try c.code.add(" });\n");
            } else if (a.value != null and std.mem.startsWith(u8, a.value.?.span.slice(c.input.source), "$")) {
                c.entries += input.factor;
                try c.code.add("binding.attribute(p, ");
                try c.code.string(n);
                try c.code.add(", .{ .node = node, .value = ");
                try c.expression(a);
                try c.code.add(" });\n");
            } else try c.literal(try std.fmt.allocPrint(c.a, " {s}", .{a.span().slice(c.input.source)}));
        }
        if (c.attr(.{ .idx = input.idx, .name = ":input" }) != null) {
            if (c.attr(.{ .idx = input.idx, .name = "type" })) |t| {
                if (oneOf(try c.value(t), "checkbox radio")) try c.literal(" data-value-format=\"checked\"");
            }
        }
        if (if_attr) |a| {
            c.entries += 2 * input.factor; // Visibility and structural membership.
            try c.code.add("const shown: bool = ");
            try c.expression(a);
            try c.code.add(";\np.visible(.{ .node = node, .value = shown });\n");
        }
        try c.literal(">");
        if (if_attr != null) {
            try c.code.add("const condition = p.beginList(.{ .node = node, .membership = if (shown) \"shown\" else \"empty\" });\nif (shown) {\n");
            try c.children(input);
            try c.code.add("}\np.endList(condition);\n");
        } else if (text_attr) |a| {
            c.entries += input.factor;
            try c.code.add("binding.text(p, .{ .node = node, .value = ");
            try c.expression(a);
            try c.code.add(" });\n");
        } else if (value_attr != null and std.mem.eql(u8, tag_name, "textarea")) {
            c.entries += input.factor;
            try c.code.add("p.textareaValue(.{ .node = node, .value = ");
            try c.expression(value_attr.?);
            try c.code.add(" });\n");
        } else try c.children(input);
        if (!node.tag.isVoid(c.input.source, .html)) try c.literal(try std.fmt.allocPrint(c.a, "</{s}>", .{tag_name}));
        try c.code.add("}\n");
    }
    fn generate(c: *Compiler) Error!void {
        try c.code.add("// Generated by zg-template. Edit the HTML template, not this file.\nconst binding = @import(\"zg_gui\").template;\npub const nodes = Scoped(.{}).nodes;\npub const project = Scoped(.{}).project;\npub fn Scoped(comptime space: binding.Namespace) type {\ncomptime space.validate();\nreturn struct {\npub const nodes = struct {\n");
        for (c.nodes.items, 0..) |node, idx| if (c.attr(.{ .idx = idx, .name = ":ref" })) |a| {
            try c.code.add("pub const @");
            try c.code.string(try c.value(a));
            try c.code.print(": u32 = space.node({d}) catch @compileError(\"template ref exceeds namespace\");\n", .{node.slot});
        };
        try c.code.add("};\npub fn project(p: anytype, view: anytype) void {\n_ = &view;\n");
        var previous: usize = 0;
        for (c.roots.items) |root| {
            try c.literal(c.input.source[previous..c.nodes.items[root].tag.span.start]);
            try c.code.print("element_{d}(p, view);\n", .{c.nodes.items[root].slot});
            previous = c.nodes.items[root].end;
        }
        try c.literal(c.input.source[previous..]);
        try c.code.add("}\n");
        for (c.nodes.items, 0..) |node, idx| try c.element(.{ .idx = idx, .in_loop = node.in_loop, .factor = node.factor });
        try c.code.print("pub const snapshot_capacity: usize = {d};\n}};\n}}\npub const snapshot_capacity = Scoped(.{{}}).snapshot_capacity;\n", .{@max(c.entries, 1)});
    }
};

fn oneOf(value: []const u8, choices: []const u8) bool {
    var it = std.mem.tokenizeScalar(u8, choices, ' ');
    while (it.next()) |choice| if (std.mem.eql(u8, value, choice)) return true;
    return false;
}
fn identifier(value: []const u8) bool {
    if (value.len == 0 or !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}
fn validPath(value: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, '.');
    while (it.next()) |part| if (!identifier(part)) return false;
    return true;
}
fn attributeName(value: []const u8) bool {
    if (value.len == 0 or !std.ascii.isLower(value[0])) return false;
    for (value) |c| if (!(std.ascii.isLower(c) or std.ascii.isDigit(c) or c == '-')) return false;
    return true;
}
fn dynamicAttribute(name: []const u8) bool {
    return oneOf(name, "class lang disabled readonly autofocus inert role title placeholder alt aria-label") or
        (std.mem.startsWith(u8, name, "aria-") and dashedName(name[5..])) or
        (std.mem.startsWith(u8, name, "data-") and dashedName(name[5..]) and !oneOf(name, "data-node-id data-event data-input-kind data-value-format data-text-format data-style-vars"));
}
fn dashedName(value: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, '-');
    while (it.next()) |part| {
        if (part.len == 0) return false;
        for (part) |c| if (!std.ascii.isLower(c)) return false;
    }
    return true;
}
fn isPhrasing(name: []const u8) bool {
    return oneOf(name, "span a strong em small b i code br label input textarea button output img");
}

test "compiler preserves literal whitespace and entities and emits leaf bindings" {
    var d = Diagnostic{};
    const source = "<p>Hello <span :ref=\"name\" :text=\"$name\"></span> &amp; goodbye.</p>";
    const code = try compile(std.testing.allocator, .{ .source = source, .name = "view.gui.html", .diagnostic = &d });
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "Hello ") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, " &amp; goodbye.") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "binding.text") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "snapshot_capacity: usize = 1") != null);
}

test "malformed structures unsupported directives and injected expressions fail at source locations" {
    for ([_][]const u8{
        "<p><div></div></p>",                       "<div><span></div>",                                                        "<div>",                                                                                                                      "<div/>",
        "<p :text=\"$name + dangerous()\"></p>",    "<p :html=\"$markup\"></p>",                                                "<p :text=\"$item.name\"></p>",                                                                                               "<input :text=\"$name\">",
        "<p :text=\"$name\">content</p>",           "<div :visible=\"$show\" hidden></div>",                                    "<button data-event=\"2\">click</button>",                                                                                    "<p CLASS=\"one\"></p>",
        "<div :loop=\"$rows\"><span></span></div>", "<div :loop=\"$rows\" :key=\"id\" :limit=\"2\"><span></span><b></b></div>", "<div :loop=\"$rows\" :key=\"id\" :limit=\"2\"><div :loop=\"$item.rows\" :key=\"id\" :limit=\"2\"><span></span></div></div>", "<p :ref=\"same\"></p><p :ref=\"same\"></p>",
    }) |source| {
        var d = Diagnostic{};
        try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = source, .name = "bad.gui.html", .diagnostic = &d }));
        try std.testing.expect(d.message.len > 0);
        try std.testing.expect(d.offset < source.len);
    }
}

fn allocationProbe(a: Allocator) !void {
    var d = Diagnostic{};
    const code = try compile(a, .{ .source = "<ul :loop=\"$rows\" :key=\"id\" :limit=\"4\"><li><span :text=\"$item.label\"></span></li></ul>", .name = "test", .diagnostic = &d });
    defer a.free(code);
}
test "compiler releases all allocations on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
