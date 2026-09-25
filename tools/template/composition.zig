//! Build-time component expansion, source locations and view/ref scopes.
const std = @import("std");
const html = @import("html-tokenizer");
const Allocator = std.mem.Allocator;
pub const Error = error{ OutOfMemory, InvalidTemplate };
pub const max_source_bytes = 256 * 1024;
pub const Source = struct { name: []const u8, source: []const u8 };
pub const Component = struct { name: []const u8, file: Source };
pub const Diagnostic = struct {
    offset: usize = 0,
    name: []const u8 = "",
    line: usize = 1,
    column: usize = 1,
    message: []const u8 = "",
};
pub const Location = struct {
    file: Source,
    offset: usize,
    pub fn diagnostic(l: Location, message: []const u8) Diagnostic {
        const before = l.file.source[0..@min(l.file.source.len, l.offset)];
        return .{
            .offset = l.offset,
            .name = l.file.name,
            .line = std.mem.count(u8, before, "\n") + 1,
            .column = before.len - (if (std.mem.lastIndexOfScalar(u8, before, '\n')) |i| i + 1 else 0) + 1,
            .message = message,
        };
    }
};
const Segment = struct { start: usize, end: usize, location: Location, exact: bool };
pub const Instance = struct { view: []const u8, ref: []const u8, location: Location, in_loop: bool = false };
pub const Document = struct {
    source: []const u8,
    segments: []const Segment,
    instances: []const Instance,
    pub fn location(d: Document, offset: usize) Location {
        for (d.segments) |s| if (offset < s.end) {
            var result = s.location;
            if (s.exact) result.offset += offset - s.start;
            return result;
        };
        const last = d.segments[d.segments.len - 1];
        return .{ .file = last.location.file, .offset = last.location.file.source.len };
    }
};

/// All returned storage belongs to the caller's build-time arena.
pub fn expand(a: Allocator, input: struct { file: Source, components: []const Component, diagnostic: *Diagnostic }) Error!Document {
    var e = Expander{ .a = a, .components = input.components, .diagnostic = input.diagnostic };
    if (input.components.len > 64) return e.reject(.{ .file = input.file, .offset = 0 }, "at most 64 component sources may be registered");
    for (input.components, 0..) |component, i| {
        if (!identifier(component.name)) return e.reject(.{ .file = component.file, .offset = 0 }, "component registration requires a simple name");
        for (input.components[0..i]) |previous| if (std.mem.eql(u8, previous.name, component.name))
            return e.reject(.{ .file = component.file, .offset = 0 }, "duplicate component registration");
    }
    try e.file(.{ .file = input.file });
    // Keep an origin even for an empty document so later parser errors map back.
    if (e.segments.items.len == 0) try e.segments.append(a, .{ .start = 0, .end = 0, .location = .{ .file = input.file, .offset = 0 }, .exact = true });
    return .{ .source = e.bytes.items, .segments = e.segments.items, .instances = e.instances.items };
}

const Expander = struct {
    a: Allocator,
    components: []const Component,
    diagnostic: *Diagnostic,
    bytes: std.ArrayList(u8) = .empty,
    segments: std.ArrayList(Segment) = .empty,
    instances: std.ArrayList(Instance) = .empty,
    active: std.ArrayList([]const u8) = .empty,

    fn reject(e: *Expander, location: Location, message: []const u8) Error {
        e.diagnostic.* = location.diagnostic(message);
        return error.InvalidTemplate;
    }
    fn append(e: *Expander, input: struct { text: []const u8, location: Location, exact: bool = true }) Error!void {
        if (e.bytes.items.len + input.text.len > max_source_bytes) return e.reject(input.location, "expanded template exceeds 256 KiB");
        if (input.text.len == 0) return;
        const start = e.bytes.items.len;
        try e.bytes.appendSlice(e.a, input.text);
        try e.segments.append(e.a, .{ .start = start, .end = e.bytes.items.len, .location = input.location, .exact = input.exact });
    }
    fn quoted(e: *Expander, input: struct { file: Source, attr: html.Tokenizer.Attr }) Error![]const u8 {
        const v = input.attr.value orelse return e.reject(.{ .file = input.file, .offset = input.attr.name.start }, "component attributes require quoted values");
        if (v.quote == .none) return e.reject(.{ .file = input.file, .offset = v.span.start }, "component attributes require quoted values");
        return v.span.slice(input.file.source);
    }
    fn scoped(e: *Expander, input: struct { scope: []const u8, value: []const u8 }) Error![]const u8 {
        if (input.scope.len == 0) return input.value;
        return std.fmt.allocPrint(e.a, "{s}.{s}", .{ input.scope, input.value });
    }
    fn file(e: *Expander, input: struct { file: Source, view: []const u8 = "", ref: []const u8 = "", in_loop: bool = false }) Error!void {
        const source = input.file.source;
        const origin = Location{ .file = input.file, .offset = 0 };
        if (source.len > max_source_bytes) return e.reject(origin, "template exceeds 256 KiB");
        if (!std.unicode.utf8ValidateSlice(source)) return e.reject(origin, "template must be valid UTF-8");
        var tokenizer = html.Tokenizer{ .language = .html };
        var cursor: usize = 0;
        var loops: std.ArrayList(struct { name: []const u8, is_loop: bool }) = .empty;
        var elements: usize = 0;
        var loop_count: usize = 0;
        while (tokenizer.next(source)) |token| switch (token) {
            .parse_error => |err| return e.reject(.{ .file = input.file, .offset = err.span.start }, @tagName(err.tag)),
            .tag => |tag| {
                const tag_name = tag.name.slice(source);
                if (tag.kind == .end or tag.kind == .end_self) {
                    const opener = loops.pop() orelse return e.reject(.{ .file = input.file, .offset = tag.span.start }, "closing tag has no opener");
                    if (tag.kind == .end_self or !std.mem.eql(u8, opener.name, tag_name)) return e.reject(.{ .file = input.file, .offset = tag.span.start }, "closing tag does not match its opener");
                    if (opener.is_loop) loop_count -= 1;
                    continue;
                }
                elements += 1;
                const in_loop = input.in_loop or loop_count != 0;
                var attrs: std.ArrayList(html.Tokenizer.Attr) = .empty;
                var scan = html.Tokenizer{ .language = .html, .return_attrs = true, .idx = tag.span.start };
                while (scan.next(source[0..tag.span.end])) |part| switch (part) {
                    .attr => |attr| {
                        if (attrs.items.len == 64) return e.reject(.{ .file = input.file, .offset = attr.name.start }, "element exceeds 64 attributes");
                        try attrs.append(e.a, attr);
                    },
                    else => {},
                };
                if (std.mem.eql(u8, tag_name, "template")) {
                    const location = Location{ .file = input.file, .offset = tag.span.start };
                    var component_name: ?[]const u8 = null;
                    var view: ?[]const u8 = null;
                    var ref: ?[]const u8 = null;
                    for (attrs.items) |attr| {
                        const name = attr.name.slice(source);
                        const target = if (std.mem.eql(u8, name, ":component")) &component_name else if (std.mem.eql(u8, name, ":view")) &view else if (std.mem.eql(u8, name, ":ref")) &ref else return e.reject(location, "component invocation only accepts :component, :view and :ref");
                        if (target.* != null) return e.reject(location, "duplicate component attribute");
                        target.* = try e.quoted(.{ .file = input.file, .attr = attr });
                    }
                    if (component_name == null or view == null or (!in_loop and ref == null)) return e.reject(location, "component invocation requires :component, :view and :ref");
                    const actual_ref = ref orelse try std.fmt.allocPrint(e.a, "loop_comp_{d}", .{e.instances.items.len});
                    if (!identifier(component_name.?) or !identifier(actual_ref)) return e.reject(location, "component and instance names must be simple identifiers");
                    const v = view.?;
                    if (v.len < 2 or v[0] != '$' or !path(v[1..])) return e.reject(location, ":view requires an explicit $field.path");
                    if (!in_loop and (isItem(v[1..]) or isOuter(v[1..]))) return e.reject(location, ":view requires an explicit $field.path outside loops");
                    if (e.active.items.len == 16) return e.reject(location, "component nesting exceeds 16");
                    for (e.active.items) |name| if (std.mem.eql(u8, name, component_name.?)) return e.reject(location, "recursive component invocation");
                    const component = for (e.components) |c| {
                        if (std.mem.eql(u8, c.name, component_name.?)) break c;
                    } else return e.reject(location, "unknown component; register its source in the build");
                    if (tag.kind != .start) return e.reject(location, "component invocation requires an explicit closing template tag");
                    const end = while (tokenizer.next(source)) |next| {
                        switch (next) {
                            .tag => |t| break t,
                            .text => |span| if (std.mem.trim(u8, span.slice(source), " \t\r\n").len != 0) return e.reject(location, "component invocation must be empty"),
                            else => return e.reject(location, "component invocation must be empty"),
                        }
                    } else return e.reject(location, "unclosed component invocation");
                    if (end.kind != .end or !std.mem.eql(u8, end.name.slice(source), "template") or std.mem.trim(u8, source[tag.span.end..end.span.start], " \t\r\n").len != 0 or std.mem.trim(u8, source[end.name.end .. end.span.end - 1], " \t\r\n").len != 0)
                        return e.reject(location, "component invocation must be empty");
                    const instance_view = if (isItem(v[1..]) or isOuter(v[1..])) v[1..] else try e.scoped(.{ .scope = input.view, .value = v[1..] });
                    const instance_ref = try e.scoped(.{ .scope = input.ref, .value = actual_ref });
                    const instance = Instance{ .view = instance_view, .ref = instance_ref, .location = location, .in_loop = in_loop };
                    if (e.instances.items.len == 256) return e.reject(location, "template exceeds 256 component instances");
                    for (e.instances.items) |previous| if (std.mem.eql(u8, previous.ref, instance.ref)) return e.reject(location, "duplicate component instance name");
                    try e.instances.append(e.a, instance);
                    try e.append(.{ .text = source[cursor..tag.span.start], .location = .{ .file = input.file, .offset = cursor } });
                    try e.active.append(e.a, component.name);
                    try e.file(.{ .file = component.file, .view = instance.view, .ref = instance.ref, .in_loop = in_loop });
                    _ = e.active.pop();
                    cursor = end.span.end;
                    continue;
                }
                var has_loop = false;
                for (attrs.items) |attr| {
                    const name = attr.name.slice(source);
                    if (std.mem.eql(u8, name, ":loop")) has_loop = true;
                    if (std.mem.eql(u8, name, ":ref")) {
                        const value = try e.quoted(.{ .file = input.file, .attr = attr });
                        if (!identifier(value)) return e.reject(.{ .file = input.file, .offset = attr.name.start }, ":ref requires a simple name");
                    }
                    if (attr.value) |v| {
                        const value = v.span.slice(source);
                        const replacement = if (std.mem.eql(u8, name, ":ref"))
                            try e.scoped(.{ .scope = input.ref, .value = value })
                        else if (input.view.len > 0 and value.len > 1 and value[0] == '$' and !isItem(value[1..]) and !isOuter(value[1..]))
                            try std.fmt.allocPrint(e.a, "${s}.{s}", .{ input.view, value[1..] })
                        else
                            continue;
                        try e.append(.{ .text = source[cursor..v.span.start], .location = .{ .file = input.file, .offset = cursor } });
                        try e.append(.{ .text = replacement, .location = .{ .file = input.file, .offset = v.span.start }, .exact = false });
                        cursor = v.span.end;
                    }
                }
                if (!tag.isVoid(source, .html) and tag.kind == .start) {
                    if (loops.items.len == 64) return e.reject(origin, "template exceeds depth 64");
                    try loops.append(e.a, .{ .name = tag_name, .is_loop = has_loop });
                    if (has_loop) loop_count += 1;
                }
                if (std.mem.eql(u8, tag_name, "textarea")) tokenizer.gotoRcData("textarea");
            },
            else => {},
        };
        if (loops.items.len != 0) return e.reject(origin, "unclosed element");
        if (elements == 0) return e.reject(origin, "template must contain an element");
        try e.append(.{ .text = source[cursor..], .location = .{ .file = input.file, .offset = cursor } });
    }
};
pub fn isItem(value: []const u8) bool {
    return std.mem.eql(u8, value, "item") or std.mem.startsWith(u8, value, "item.");
}
pub fn isOuter(value: []const u8) bool {
    return std.mem.eql(u8, value, "outer") or std.mem.startsWith(u8, value, "outer.");
}
fn identifier(value: []const u8) bool {
    if (value.len == 0 or !(std.ascii.isAlphabetic(value[0]) or value[0] == '_')) return false;
    for (value) |byte| if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    return true;
}
fn path(value: []const u8) bool {
    var parts = std.mem.splitScalar(u8, value, '.');
    while (parts.next()) |part| if (!identifier(part)) return false;
    return true;
}
