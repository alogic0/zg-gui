//! Native template compiler. No tokenizer or source text is linked into WASM.
const std = @import("std");
const html = @import("html-tokenizer");
const syntax = @import("template-syntax");
const Allocator = std.mem.Allocator;
const composition = @import("composition.zig");
const Attr = html.Tokenizer.Attr;
const Error = error{ OutOfMemory, InvalidTemplate };
pub const max_source_bytes = composition.max_source_bytes;
pub const Diagnostic = composition.Diagnostic;
pub const Component = composition.Component;
pub const Input = struct {
    source: []const u8,
    name: []const u8,
    diagnostic: *Diagnostic,
    components: []const Component = &.{},
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
    const document = try composition.expand(arena.allocator(), .{
        .file = .{ .source = input.source, .name = input.name },
        .components = input.components,
        .diagnostic = input.diagnostic,
    });
    var expanded = input;
    expanded.source = document.source;
    var compiler = Compiler{ .a = arena.allocator(), .input = expanded, .document = document, .code = .{ .allocator = arena.allocator() } };
    try compiler.parse();
    for (compiler.roots.items) |idx| try compiler.validate(.{ .idx = idx, .in_loop = false });
    try compiler.generate();
    return allocator.dupe(u8, compiler.code.bytes.items);
}

const Compiler = struct {
    a: Allocator,
    input: Input,
    document: composition.Document,
    code: Code,
    nodes: std.ArrayList(Node) = .empty,
    roots: std.ArrayList(usize) = .empty,
    entries: usize = 0,

    fn reject(c: *Compiler, at: usize, message: []const u8) Error {
        c.input.diagnostic.* = c.document.location(at).diagnostic(message);
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
                        if (!oneOf(tag_name, "main header footer section article aside nav div p span h1 h2 h3 h4 h5 h6 a strong em small b i code pre br hr form fieldset legend label input textarea button output ul ol li dl dt dd img details summary table caption colgroup col thead tbody tfoot tr th td select optgroup option svg g defs symbol path circle ellipse rect line polyline polygon use title")) {
                            return c.reject(tag.name.start, "unsupported element; use the documented HTML fragment subset");
                        }
                        if (tag.kind == .start_self and !tag.isVoid(c.input.source, .html) and !isSvg(tag_name)) return c.reject(tag.span.start, "non-void HTML elements require an explicit closing tag");
                        const parent_name = if (stack.items.len > 0) c.name(stack.items[stack.items.len - 1]) else "";
                        for (stack.items) |parent| {
                            const ancestor = c.name(parent);
                            if (!isSvg(parent_name) and oneOf(ancestor, "p h1 h2 h3 h4 h5 h6") and !isPhrasing(tag_name)) return c.reject(tag.name.start, "block content would implicitly close a phrasing-only ancestor");
                            if (oneOf(tag_name, "a button form") and std.mem.eql(u8, tag_name, ancestor)) return c.reject(tag.name.start, "nested interactive element would be repaired by the browser");
                            if (std.mem.eql(u8, ancestor, "button") and oneOf(tag_name, "a input textarea button select")) return c.reject(tag.name.start, "interactive content is not allowed inside a button");
                        }
                        const grouped = std.mem.eql(u8, parent_name, "div") and stack.items.len >= 2 and std.mem.eql(u8, c.name(stack.items[stack.items.len - 2]), "dl");
                        if (grouped and !oneOf(tag_name, "dt dd")) return c.reject(tag.name.start, "description list groups require terms and descriptions");
                        if (oneOf(tag_name, "dt dd")) {
                            if (!std.mem.eql(u8, parent_name, "dl") and !grouped) return c.reject(tag.name.start, "description term/value requires a dl or its direct div group");
                        }
                        if (structureError(.{ .parent = parent_name, .child = tag_name })) |message| return c.reject(tag.name.start, message);
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
                        if (!tag.isVoid(c.input.source, .html) and tag.kind != .start_self) try stack.append(c.a, idx);
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

    fn validate(c: *Compiler, input: struct { idx: usize, in_loop: bool, in_condition: bool = false, factor: usize = 1 }) Error!void {
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
                if (!validPath(ref) or input.in_loop) return c.reject(a.name.start, ":ref requires a simple name outside loops");
                for (c.nodes.items[0..input.idx], 0..) |_, previous| {
                    if (c.attr(.{ .idx = previous, .name = ":ref" })) |other| {
                        if (std.mem.eql(u8, ref, try c.value(other))) return c.reject(a.name.start, "duplicate :ref");
                    }
                }
                continue;
            }
            if (std.mem.eql(u8, n, ":slot")) {
                if (input.in_loop or input.in_condition)
                    return c.reject(a.name.start, ":slot is not supported inside loops or conditions");
                try c.binding(.{ .attr = a, .in_loop = false });
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
                    if (!oneOf(tag_name, "input textarea select")) return c.reject(a.name.start, ":value requires input, textarea or select");
                } else if (std.mem.eql(u8, n, ":visible")) {
                    has_visible = true;
                } else if (std.mem.eql(u8, n, ":checked")) {
                    const type_attr = c.attr(.{ .idx = input.idx, .name = "type" }) orelse return c.reject(a.name.start, ":checked requires a static checkbox or radio type");
                    if (!std.mem.eql(u8, tag_name, "input") or !oneOf(try c.value(type_attr), "checkbox radio")) return c.reject(a.name.start, ":checked requires a checkbox or radio");
                } else if (std.mem.eql(u8, n, ":input")) {
                    if (!oneOf(tag_name, "input textarea select")) return c.reject(a.name.start, ":input requires input, textarea or select");
                } else if (!std.mem.eql(u8, n, ":on-click")) {
                    return c.reject(a.name.start, "unknown GUI directive");
                }
                try c.binding(.{ .attr = a, .in_loop = input.in_loop });
            } else {
                if (!(attributeName(n) or (isSvg(tag_name) and oneOf(n, "viewBox preserveAspectRatio"))) or std.mem.startsWith(u8, n, "on") or oneOf(n, "data-node-id data-event data-input-kind data-select-value")) return c.reject(a.name.start, "reserved or unsupported attribute name");
                if (a.value) |v| if (std.mem.startsWith(u8, v.span.slice(c.input.source), "$")) {
                    if (!(dynamicAttribute(n) or (isSvg(tag_name) and oneOf(n, "viewBox d fill stroke stroke-width x y x1 x2 y1 y2 cx cy r rx ry width height points transform")) or (std.mem.eql(u8, tag_name, "use") and std.mem.eql(u8, n, "href")) or (std.mem.eql(u8, tag_name, "option") and std.mem.eql(u8, n, "value")))) return c.reject(a.name.start, "unsupported dynamic attribute; use a property directive for form state");
                    try c.binding(.{ .attr = a, .in_loop = input.in_loop });
                };
            }
        }
        if (c.attr(.{ .idx = input.idx, .name = ":slot" })) |a| {
            if (!oneOf(tag_name, "div section") or has_text or has_value or has_if or has_loop or
                std.mem.trim(u8, c.input.source[node.tag.span.end..node.close_start], " \t\r\n").len != 0)
                return c.reject(a.name.start, ":slot requires an empty div or section with no other content owner");
        }
        if (oneOf(tag_name, "dl table colgroup thead tbody tfoot tr select optgroup")) {
            if (has_text) return c.reject(node.tag.span.start, "this container requires structural children, not text");
            var previous: usize = node.tag.span.end;
            for (node.children.items) |child| {
                if (std.mem.trim(u8, c.input.source[previous..c.nodes.items[child].tag.span.start], " \t\r\n").len != 0) return c.reject(previous, "only whitespace is allowed between structural children");
                previous = c.nodes.items[child].end;
            }
            if (std.mem.trim(u8, c.input.source[previous..node.close_start], " \t\r\n").len != 0) return c.reject(previous, "only whitespace is allowed between structural children");
        }
        if (std.mem.eql(u8, tag_name, "select") and c.attr(.{ .idx = input.idx, .name = "multiple" }) != null) return c.reject(node.tag.span.start, "multiple selection requires a dedicated value model");
        if (has_text and (is_void or has_value or has_if or has_loop or std.mem.eql(u8, tag_name, "textarea"))) return c.reject(node.tag.span.start, ":text conflicts with this element or its content owner");
        if ((has_text or (has_value and std.mem.eql(u8, tag_name, "textarea"))) and std.mem.trim(u8, c.input.source[node.tag.span.end..node.close_start], " \t\r\n").len > 0) return c.reject(node.tag.span.start, "text/value bindings require empty content");
        if ((has_if and (is_void or has_visible or has_value)) or (has_loop and (is_void or (has_value and !std.mem.eql(u8, tag_name, "select"))))) return c.reject(node.tag.span.start, "conflicting structural or visibility directives");
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
        for (node.children.items) |child| try c.validate(.{ .idx = child, .in_loop = input.in_loop or has_loop, .in_condition = input.in_condition or has_if, .factor = input.factor * (node.loop_limit orelse 1) });
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
        const location = c.document.location(a.name.start).diagnostic("");
        try c.code.string(try std.fmt.allocPrint(c.a, "{s}:{d}:{d}", .{ location.name, location.line, location.column }));
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
        if (c.attr(.{ .idx = input.idx, .name = ":slot" })) |a| {
            try c.code.add("binding.projectSlot(p, .{ .value = ");
            try c.expression(a);
            try c.code.print(", .node = space.node({d}) catch unreachable }});\n", .{node.slot});
        } else if (node.loop_limit) |limit| {
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
            try c.code.print("element_{d}(p, view, space, item, key);\n", .{c.nodes.items[child].slot});
            try c.code.print("p.endChild(child);\n}}\np.order(.{{ .owner = space.node({d}) catch unreachable, .nodes = ids[0..items.len] }});\n}}\n", .{node.slot});
        } else {
            var previous: usize = node.tag.span.end;
            for (node.children.items) |child| {
                try c.literal(c.input.source[previous..c.nodes.items[child].tag.span.start]);
                try c.code.print("element_{d}(p, view, space{s});\n", .{ c.nodes.items[child].slot, if (input.in_loop) ", item, key" else "" });
                previous = c.nodes.items[child].end;
            }
            try c.literal(c.input.source[previous..node.close_start]);
        }
    }

    fn element(c: *Compiler, input: Emission) Error!void {
        const node = c.nodes.items[input.idx];
        const tag_name = c.name(input.idx);
        try c.code.print("fn element_{d}(p: anytype, view: anytype, space: binding.Namespace{s}) void {{\n_ = &view;\n{s}const node: u32 = ", .{ node.slot, if (input.in_loop) ", item: anytype, key: u32" else "", if (input.in_loop) "_ = &item;\n" else "" });
        try c.id(.{ .slot = node.slot, .in_loop = input.in_loop });
        try c.code.add(";\n");
        try c.literal(try std.fmt.allocPrint(c.a, "<{s}", .{tag_name}));
        try c.code.add("p.node(node);\n");
        const text_attr = c.attr(.{ .idx = input.idx, .name = ":text" });
        const value_attr = c.attr(.{ .idx = input.idx, .name = ":value" });
        const if_attr = c.attr(.{ .idx = input.idx, .name = ":if" });
        for (node.attrs) |a| {
            const n = a.name.slice(c.input.source);
            if (oneOf(n, ":ref :key :limit :loop :text :if :slot")) continue;
            if (std.mem.eql(u8, n, ":value")) {
                if (oneOf(tag_name, "textarea select")) continue;
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
        if (value_attr != null and std.mem.eql(u8, tag_name, "select")) {
            c.entries += input.factor;
            try c.code.add("binding.attribute(p, \"data-select-value\", .{ .node = node, .value = ");
            try c.expression(value_attr.?);
            try c.code.add(" });\n");
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
        if (value_attr != null and std.mem.eql(u8, tag_name, "select")) {
            c.entries += input.factor;
            try c.code.add("p.selectedValue(.{ .node = node, .value = ");
            try c.expression(value_attr.?);
            try c.code.add(" });\n");
        }
        if (!node.tag.isVoid(c.input.source, .html)) try c.literal(try std.fmt.allocPrint(c.a, "</{s}>", .{tag_name}));
        try c.code.add("}\n");
    }
    fn generate(c: *Compiler) Error!void {
        try c.code.add("// Generated by zg-template. Edit the HTML template, not this file.\nconst binding = @import(\"zg_gui\").template;\npub const nodes = Scoped(.{}).nodes;\npub const project = Scoped(.{}).project;\npub const projectAt = Runtime.projectAt;\npub const snapshot_capacity = Runtime.snapshot_capacity;\npub const Refs = struct {\n");
        for (c.nodes.items, 0..) |_, idx| if (c.attr(.{ .idx = idx, .name = ":ref" })) |a| {
            try c.code.add("@");
            try c.code.string(try c.value(a));
            try c.code.add(": u32,\n");
        };
        try c.code.add("};\npub fn nodesAt(space: binding.Namespace) error{NamespaceOverflow}!Refs {\n");
        try c.code.print("_ = try space.node({d});\nreturn .{{\n", .{@max(c.nodes.items.len, 1)});
        for (c.nodes.items, 0..) |node, idx| if (c.attr(.{ .idx = idx, .name = ":ref" })) |a| {
            try c.code.add(".@");
            try c.code.string(try c.value(a));
            try c.code.print(" = try space.node({d}),\n", .{node.slot});
        };
        try c.code.add("};\n}\npub fn Scoped(comptime space: binding.Namespace) type {\ncomptime space.validate();\nreturn struct {\npub const nodes = struct {\n");
        for (c.nodes.items, 0..) |node, idx| if (c.attr(.{ .idx = idx, .name = ":ref" })) |a| {
            try c.code.add("pub const @");
            try c.code.string(try c.value(a));
            try c.code.print(": u32 = space.node({d}) catch @compileError(\"template ref exceeds namespace\");\n", .{node.slot});
        };
        try c.code.add("};\npub const snapshot_capacity = Runtime.snapshot_capacity;\npub fn project(p: anytype, view: anytype) void { Runtime.projectAt(p, view, space); }\n};\n}\nconst Runtime = struct {\npub fn projectAt(p: anytype, view: anytype, space: binding.Namespace) void {\n_ = &view;\n");
        try c.code.print("_ = space.node({d}) catch {{ p.html.failed = true; return; }};\n", .{@max(c.nodes.items.len, 1)});
        for (c.document.instances) |instance| {
            const location = instance.location.diagnostic("");
            const label = try std.fmt.allocPrint(c.a, "{s}:{d}:{d}", .{ location.name, location.line, location.column });
            try c.code.add("binding.componentInput(binding.get(view, ");
            try c.code.string(instance.view);
            try c.code.add(", ");
            try c.code.string(label);
            try c.code.add("), ");
            try c.code.string(label);
            try c.code.add(");\n");
        }
        var previous: usize = 0;
        for (c.roots.items) |root| {
            try c.literal(c.input.source[previous..c.nodes.items[root].tag.span.start]);
            try c.code.print("element_{d}(p, view, space);\n", .{c.nodes.items[root].slot});
            previous = c.nodes.items[root].end;
        }
        try c.literal(c.input.source[previous..]);
        try c.code.add("}\n");
        for (c.nodes.items, 0..) |node, idx| try c.element(.{ .idx = idx, .in_loop = node.in_loop, .factor = node.factor });
        try c.code.print("pub const snapshot_capacity: usize = {d};\n}};\n", .{@max(c.entries, 1)});
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
    return oneOf(name, "class lang disabled readonly autofocus inert role title placeholder alt id for aria-label") or
        (std.mem.startsWith(u8, name, "aria-") and dashedName(name[5..])) or
        (std.mem.startsWith(u8, name, "data-") and dashedName(name[5..]) and !oneOf(name, "data-node-id data-event data-input-kind data-value-format data-text-format data-style-vars data-select-value"));
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
    return oneOf(name, "span a strong em small b i code br label input textarea button output img select svg");
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

fn isSvg(name: []const u8) bool {
    return oneOf(name, "svg g defs symbol path circle ellipse rect line polyline polygon use title");
}
fn structureError(input: struct { parent: []const u8, child: []const u8 }) ?[]const u8 {
    const p = input.parent;
    const n = input.child;
    if (std.mem.eql(u8, p, "dl") and !oneOf(n, "div dt dd")) return "description lists require terms, descriptions or div groups";
    if (isSvg(p)) {
        if (!isSvg(n) or !oneOf(p, "svg g defs symbol")) return "invalid SVG child structure";
    } else if (isSvg(n) and !std.mem.eql(u8, n, "svg")) return "SVG elements require an SVG container";
    const valid = if (std.mem.eql(u8, p, "table")) oneOf(n, "caption colgroup thead tbody tfoot") else if (oneOf(p, "thead tbody tfoot")) std.mem.eql(u8, n, "tr") else if (std.mem.eql(u8, p, "tr")) oneOf(n, "th td") else if (std.mem.eql(u8, p, "colgroup")) std.mem.eql(u8, n, "col") else if (std.mem.eql(u8, p, "select")) oneOf(n, "option optgroup") else if (std.mem.eql(u8, p, "optgroup")) std.mem.eql(u8, n, "option") else !std.mem.eql(u8, p, "option");
    if (!valid) return "invalid table or select child structure; use explicit section elements";
    if (oneOf(n, "caption colgroup thead tbody tfoot") and !std.mem.eql(u8, p, "table")) return "table section requires a table parent";
    if (std.mem.eql(u8, n, "tr") and !oneOf(p, "thead tbody tfoot")) return "tr requires an explicit table section";
    if (oneOf(n, "th td") and !std.mem.eql(u8, p, "tr")) return "table cell requires a tr parent";
    if (std.mem.eql(u8, n, "col") and !std.mem.eql(u8, p, "colgroup")) return "col requires a colgroup parent";
    if (std.mem.eql(u8, n, "option") and !oneOf(p, "select optgroup")) return "option requires a select or optgroup parent";
    if (std.mem.eql(u8, n, "optgroup") and !std.mem.eql(u8, p, "select")) return "optgroup requires a select parent";
    return null;
}

test "table select and SVG structures are validated before browser repair" {
    for ([_][]const u8{
        "<table><tr><td>x</td></tr></table>",
        "<table>text<tbody></tbody></table>",
        "<tbody><div></div></tbody>",
        "<div><td>x</td></div>",
        "<select><div>x</div></select>",
        "<select :text=\"$label\"></select>",
        "<select multiple></select>",
        "<select><option><span>x</span></option></select>",
        "<svg><foreignObject></foreignObject></svg>",
        "<svg><path><circle /></path></svg>",
        "<div><path /></div>",
        "<div data-select-value=\"x\"></div>",
    }) |source| {
        var d = Diagnostic{};
        try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = source, .name = "bad-controls.gui.html", .diagnostic = &d }));
    }
    var d = Diagnostic{};
    const code = try compile(std.testing.allocator, .{ .source = "<section><h2><svg><path d=\"M0 0h1\" /></svg></h2><svg viewBox=\"0 0 24 24\"><path d=\"M0 0h1\" /></svg><table><tbody><tr><td>x</td></tr></tbody></table><select :value=\"$selected\" :input=\"$input\"><option value=\"a\">A</option></select></section>", .name = "controls.gui.html", .diagnostic = &d });
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "p.selectedValue") != null);
}

const component_fixture = Component{ .name = "field", .file = .{ .name = "field.gui.html", .source = "<label><span :text=\"$label\"></span><input :ref=\"input\" :value=\"$value\"></label>" } };
const component_invocation = "<template :component=\"field\" :view=\"$first\" :ref=\"first\"></template>";

test "components scope views and references and derive combined capacity" {
    var d = Diagnostic{};
    const code = try compile(std.testing.allocator, .{ .source = component_invocation ++ "<template :component=\"field\" :view=\"$second\" :ref=\"second\"></template>", .name = "parent.gui.html", .components = &.{component_fixture}, .diagnostic = &d });
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "first.input") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "second.value") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "snapshot_capacity: usize = 4") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "<template") == null);
    try std.testing.expect(std.mem.indexOf(u8, code, "field.gui.html:1:14") != null);
}

test "component composition rejects invalid boundaries names loops and recursion" {
    const recursive = Component{ .name = "recursive", .file = .{ .name = "recursive.gui.html", .source = "<template :component=\"recursive\" :view=\"$child\" :ref=\"child\"></template>" } };
    for ([_][]const u8{
        "<template :component=\"missing\" :view=\"$first\" :ref=\"first\"></template>",
        "<template :component=\"field\" :view=\"$first\"></template>",
        "<template :component=\"field\" :view=\"$first + bad()\" :ref=\"first\"></template>",
        "<template :component=\"field\" :view=\"$first\" :ref=\"first\">text</template>",
        "<template :component=\"field\" :view=\"$first\" :ref=\"first\"></template extra>",
        component_invocation ++ component_invocation,
        "<ul :loop=\"$rows\" :key=\"id\" :limit=\"2\"><li>" ++ component_invocation ++ "</li></ul>",
        "<button>" ++ component_invocation ++ "</button>",
        "<template :component=\"recursive\" :view=\"$first\" :ref=\"first\"></template>",
    }) |source| {
        var d = Diagnostic{};
        try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = source, .name = "parent.gui.html", .components = &.{ component_fixture, recursive }, .diagnostic = &d }));
        try std.testing.expect(d.message.len != 0 and d.name.len != 0);
    }
    var d = Diagnostic{};
    try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = component_invocation, .name = "parent.gui.html", .components = &.{ component_fixture, component_fixture }, .diagnostic = &d }));
    const broken = Component{ .name = "field", .file = .{ .name = "broken.gui.html", .source = "<div>\n<span :text=\"$bad + expression\"></span></div>" } };
    try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = component_invocation, .name = "parent.gui.html", .components = &.{broken}, .diagnostic = &d }));
    try std.testing.expectEqualStrings("broken.gui.html", d.name);
    try std.testing.expectEqual(@as(usize, 2), d.line);
    try std.testing.expectEqual(@as(usize, 7), d.column);
}

fn componentAllocationProbe(a: Allocator) !void {
    var d = Diagnostic{};
    const code = try compile(a, .{ .source = component_invocation, .name = "parent.gui.html", .components = &.{component_fixture}, .diagnostic = &d });
    defer a.free(code);
}
test "component expansion releases every allocation on failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, componentAllocationProbe, .{});
}

test "components enforce expansion and nesting bounds" {
    var d = Diagnostic{};
    const large = try std.testing.allocator.alloc(u8, max_source_bytes);
    defer std.testing.allocator.free(large);
    @memset(large, 'a');
    @memcpy(large[0..3], "<p>");
    @memcpy(large[large.len - 4 ..], "</p>");
    const oversized = Component{ .name = "field", .file = .{ .name = "large.gui.html", .source = large } };
    try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = "<div>" ++ component_invocation ++ "</div>", .name = "parent", .components = &.{oversized}, .diagnostic = &d }));
    try std.testing.expectEqualStrings("expanded template exceeds 256 KiB", d.message);
    const whitespace = "<template :component=\"field\" :view=\"$first\" :ref=\"first\"> \n </template>";
    const code = try compile(std.testing.allocator, .{ .source = whitespace, .name = "parent", .components = &.{component_fixture}, .diagnostic = &d });
    defer std.testing.allocator.free(code);
    // A component cannot balance an opener belonging to its caller.
    const broken = Component{ .name = "field", .file = .{ .name = "broken", .source = "</div><div>" } };
    try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = "<div>" ++ component_invocation ++ "</div>", .name = "parent", .components = &.{broken}, .diagnostic = &d }));
}

test "description lists validate term and value ownership" {
    for ([_][]const u8{ "<dt>Term</dt>", "<div><dd>Value</dd></div>", "<dl><p>wrong</p></dl>", "<dl><div><span>wrong</span></div></dl>", "<dl>text<dt>Term</dt></dl>", "<dl><div><div><dd>Value</dd></div></div></dl>" }) |source| {
        var d = Diagnostic{};
        try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = source, .name = "description.gui.html", .diagnostic = &d }));
    }
    var d = Diagnostic{};
    const code = try compile(std.testing.allocator, .{ .source = "<dl><dt>Term</dt><dd :text=\"$value\"></dd></dl><dl><div><dt>Term</dt><dd :text=\"$value\"></dd></div></dl>", .name = "description.gui.html", .diagnostic = &d });
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "snapshot_capacity: usize = 2") != null);
}

test "typed projection slots reject competing owners and ambiguous placement" {
    var d = Diagnostic{};
    const code = try compile(std.testing.allocator, .{ .source = "<section :ref=\"body\" :slot=\"$children\"></section>", .name = "slots.gui.html", .diagnostic = &d });
    defer std.testing.allocator.free(code);
    try std.testing.expect(std.mem.indexOf(u8, code, "binding.projectSlot") != null);
    try std.testing.expect(std.mem.indexOf(u8, code, "pub fn nodesAt") != null);
    for ([_][]const u8{
        "<div :slot=\"literal\"></div>",
        "<div :slot=\"$children\">content</div>",
        "<div :slot=\"$children\"><p></p></div>",
        "<div :slot=\"$children\" :text=\"$text\"></div>",
        "<div :slot=\"$children\" :if=\"$shown\"></div>",
        "<div :if=\"$shown\"><div :slot=\"$children\"></div></div>",
        "<ul :loop=\"$rows\" :key=\"id\" :limit=\"2\"><div :slot=\"$children\"></div></ul>",
        "<span :slot=\"$children\"></span>",
        "<input :slot=\"$children\">",
    }) |source| {
        try std.testing.expectError(error.InvalidTemplate, compile(std.testing.allocator, .{ .source = source, .name = "bad-slot.gui.html", .diagnostic = &d }));
    }
}
