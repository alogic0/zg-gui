//! Shared bounded layout and drawing for sequence diagrams.
const std = @import("std");
const parser = @import("sequence_parser.zig");
const font_mod = @import("font_metrics.zig");
const svg_mod = @import("svg.zig");

pub const LayoutOptions = struct {
    font_size: f32 = 14,
    min_col_spacing: f32 = 80,
    participant_padding_x: f32 = 16,
    participant_header_height: f32 = 36,
    row_height: f32 = 48,
    activation_width: f32 = 12,
    margin_x: f32 = 40,
    margin_y: f32 = 30,
    max_label_width: f32 = 200,
};
pub const ParticipantGeometry = struct { id: u32, center_x: f32, box_width: f32, box_height: f32, label: []const u8, is_actor: bool };
pub const ActivationSpan = struct { participant: u32, y_start: f32, y_end: f32, depth: u16, event_index: ?u32 = null };
const NoteBox = struct { x: f32, width: f32, height: f32 };

pub const SequenceLayout = struct {
    diagram: *const parser.SequenceDiagram,
    options: LayoutOptions,
    font: font_mod.Font,
    participants: []ParticipantGeometry,
    total_width: f32,
    total_height: f32,
    header_bottom_y: f32,
    footer_top_y: f32,
    arena: std.heap.ArenaAllocator,
    participant_text: []font_mod.TextLayout,
    event_text: []font_mod.TextLayout,
    event_y: []f32,
    activations: []ActivationSpan,
    title_text: font_mod.TextLayout,

    pub fn solve(allocator: std.mem.Allocator, diagram: *const parser.SequenceDiagram, options: LayoutOptions) !SequenceLayout {
        inline for (.{ "font_size", "min_col_spacing", "participant_header_height", "row_height", "activation_width", "max_label_width" }) |field| {
            const value = @field(options, field);
            if (!std.math.isFinite(value) or value <= 0) return error.InvalidOptions;
        }
        inline for (.{ "participant_padding_x", "margin_x", "margin_y" }) |field| {
            const value = @field(options, field);
            if (!std.math.isFinite(value) or value < 0) return error.InvalidOptions;
        }
        const count = diagram.participants.items.len;
        if (count == 0) return error.EmptyDiagram;
        if (count > std.math.maxInt(u16) or diagram.events.items.len > std.math.maxInt(u32)) return error.LimitExceeded;
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const a = arena.allocator();
        const font = font_mod.Font.init(options.font_size);
        const parts = try a.alloc(ParticipantGeometry, count);
        const part_text = try a.alloc(font_mod.TextLayout, count);
        var header_height = options.participant_header_height;
        for (diagram.participants.items, 0..) |participant, i| {
            part_text[i] = try font.wrapText(a, participant.label, options.max_label_width);
            header_height = @max(header_height, part_text[i].height + 16);
            parts[i] = .{ .id = @intCast(i), .center_x = 0, .box_width = @max(options.min_col_spacing, part_text[i].width + 2 * options.participant_padding_x), .box_height = 0, .label = participant.label, .is_actor = participant.is_actor };
        }
        for (parts) |*part| part.box_height = header_height;
        const event_text = try a.alloc(font_mod.TextLayout, diagram.events.items.len);
        const event_y = try a.alloc(f32, diagram.events.items.len);
        var number: usize = 1;
        for (diagram.events.items, 0..) |event, i| {
            const text: []const u8 = switch (event) {
                .message => |m| blk: {
                    if (m.from >= count or m.to >= count) return error.InvalidDiagram;
                    if (!diagram.autonumber) break :blk m.text;
                    const value = try std.fmt.allocPrint(a, "[{d}] {s}", .{ number, m.text });
                    number += 1;
                    break :blk value;
                },
                .note => |n| blk: {
                    if (n.first_participant >= count or (n.second_participant != null and n.second_participant.? >= count)) return error.InvalidDiagram;
                    break :blk n.text;
                },
                .activate, .deactivate => |id| blk: {
                    if (id >= count) return error.InvalidDiagram;
                    break :blk "";
                },
            };
            event_text[i] = try font.wrapText(a, text, options.max_label_width);
        }
        parts[0].center_x = options.margin_x + parts[0].box_width / 2;
        for (parts[1..], 1..) |*part, i| {
            var distance = (parts[i - 1].box_width + part.box_width) / 2 + 20;
            for (diagram.events.items, 0..) |event, j| if (event == .message) {
                const m = event.message;
                if ((m.from == i - 1 and m.to == i) or (m.from == i and m.to == i - 1)) distance = @max(distance, event_text[j].width + 40);
            };
            part.center_x = parts[i - 1].center_x + distance;
        }
        var left: f32 = options.margin_x;
        var right = parts[count - 1].center_x + parts[count - 1].box_width / 2;
        for (diagram.events.items, 0..) |event, i| switch (event) {
            .note => |note| {
                const box = noteBox(parts, note, event_text[i]);
                left = @min(left, box.x);
                right = @max(right, box.x + box.width);
            },
            .message => |message| if (message.from == message.to) {
                right = @max(right, parts[message.from].center_x + 42 + event_text[i].width);
            },
            else => {},
        };
        const shift = options.margin_x - left;
        for (parts) |*part| part.center_x += shift;
        const title_text = try font.wrapText(a, diagram.title orelse "", options.max_label_width * 2);
        const header_bottom = options.margin_y + (if (diagram.title != null) title_text.height + 16 else @as(f32, 0)) + header_height;
        var y = header_bottom + 12;
        var timeline_y = y;
        const stacks = try a.alloc(std.ArrayList(f32), count);
        for (stacks) |*stack| stack.* = .empty;
        var activations = std.ArrayList(ActivationSpan).empty;
        for (diagram.events.items, 0..) |event, i| {
            event_y[i] = y;
            switch (event) {
                .activate => |id| try stacks[id].append(a, timeline_y),
                .deactivate => |id| if (stacks[id].pop()) |start| {
                    try activations.append(a, .{ .participant = id, .y_start = start, .y_end = timeline_y, .depth = @intCast(stacks[id].items.len), .event_index = @intCast(i) });
                },
                .message => |m| {
                    event_y[i] = y + event_text[i].height + 10;
                    timeline_y = event_y[i];
                    y += @max(options.row_height, event_text[i].height + (if (m.from == m.to) @as(f32, 40) else 24));
                },
                .note => {
                    y += @max(options.row_height, event_text[i].height + 24);
                    timeline_y = y;
                },
            }
        }
        for (stacks, 0..) |stack, id| for (stack.items, 0..) |start, depth| {
            try activations.append(a, .{ .participant = @intCast(id), .y_start = start, .y_end = y, .depth = @intCast(depth) });
        };
        return .{ .diagram = diagram, .options = options, .font = font, .participants = parts, .total_width = @max(right + shift + options.margin_x, title_text.width + 2 * options.margin_x), .total_height = y + 16 + header_height + options.margin_y, .header_bottom_y = header_bottom, .footer_top_y = y + 16, .arena = arena, .participant_text = part_text, .event_text = event_text, .event_y = event_y, .activations = activations.items, .title_text = title_text };
    }

    pub fn deinit(self: *SequenceLayout, _: std.mem.Allocator) void {
        self.arena.deinit();
    }

    pub fn renderSvg(self: *const SequenceLayout, allocator: std.mem.Allocator) ![]u8 {
        var svg = svg_mod.SvgWriter.init(allocator);
        errdefer svg.deinit();
        try self.draw(.{ .allocator = allocator, .sink = &svg });
        return svg.toOwnedSlice();
    }

    fn drawText(self: *const SequenceLayout, sink: anytype, input: struct { x: f32, top: f32, anchor: svg_mod.TextAnchor = .middle, class: []const u8, layout: font_mod.TextLayout }) !void {
        for (input.layout.lines, 0..) |line, i| try sink.textSingleLine(input.x, input.top + self.font.baselineOffset() + @as(f32, @floatFromInt(i)) * self.font.lineHeight(), input.anchor, input.class, line.text);
    }

    pub fn draw(self: *const SequenceLayout, input: anytype) !void {
        const sink = input.sink;
        try sink.startSvg(self.total_width, self.total_height);
        try sink.writeStandardDefs();
        if (self.diagram.title != null) {
            try sink.entity(.{ .kind = .title });
            try self.drawText(sink, .{ .x = self.total_width / 2, .top = self.options.margin_y, .class = "zig-diagram-title", .layout = self.title_text });
        }
        try sink.startGroup("zig-diagram-lifelines");
        for (self.participants) |part| {
            try sink.entity(.{ .kind = .lifeline, .name = self.diagram.participants.items[part.id].name });
            try sink.lineDotted(part.center_x, self.header_bottom_y, part.center_x, self.footer_top_y, "5,5", "zig-diagram-lifeline", null);
        }
        try sink.endGroup();
        try sink.startGroup("zig-diagram-activations");
        for (self.activations) |span| {
            const part = self.participants[span.participant];
            if (span.event_index) |index| try sink.entity(.{ .kind = .event, .index = index }) else try sink.entity(.{ .kind = .activation, .name = self.diagram.participants.items[part.id].name, .index = @as(u32, span.depth) });
            try sink.rect(part.center_x - self.options.activation_width / 2 + @as(f32, @floatFromInt(span.depth)) * 3, span.y_start, self.options.activation_width, @max(0, span.y_end - span.y_start), 2, 2, "zig-diagram-activation");
        }
        try sink.endGroup();
        try sink.startGroup("zig-diagram-messages");
        for (self.diagram.events.items, 0..) |event, i| {
            try sink.entity(.{ .kind = .event, .index = @as(u32, @intCast(i)) });
            const y = self.event_y[i];
            switch (event) {
                .message => |m| {
                    const from = self.participants[m.from].center_x;
                    const to = self.participants[m.to].center_x;
                    const marker = switch (m.msg_type) {
                        .solid_arrow, .dotted_arrow => "arrow",
                        .solid_cross, .dotted_cross => "cross",
                        else => "arrow-open",
                    };
                    const dotted = switch (m.msg_type) {
                        .dotted_arrow, .dotted_open, .dotted_async, .dotted_cross => true,
                        else => false,
                    };
                    const class = if (dotted) "zig-diagram-edge-line zig-diagram-edge-dotted" else "zig-diagram-edge-line";
                    if (m.from == m.to) {
                        const d = try std.fmt.allocPrint(input.allocator, "M {d:.1} {d:.1} L {d:.1} {d:.1} L {d:.1} {d:.1} L {d:.1} {d:.1}", .{ from, y, from + 36, y, from + 36, y + 24, from, y + 24 });
                        defer input.allocator.free(d);
                        try sink.path(d, if (dotted) "zig-diagram-edge-line zig-diagram-self-arrow zig-diagram-edge-dotted" else "zig-diagram-edge-line zig-diagram-self-arrow", marker);
                        try self.drawText(sink, .{ .x = from + 42, .top = y + 12 - self.event_text[i].height / 2, .anchor = .start, .class = "zig-diagram-label", .layout = self.event_text[i] });
                    } else {
                        if (dotted) try sink.lineDotted(from, y, to, y, "4,4", class, marker) else try sink.line(from, y, to, y, class, marker);
                        try self.drawText(sink, .{ .x = (from + to) / 2, .top = y - self.event_text[i].height - 8, .class = "zig-diagram-label", .layout = self.event_text[i] });
                    }
                },
                .note => |note| {
                    const box = noteBox(self.participants, note, self.event_text[i]);
                    try sink.rect(box.x, y, box.width, box.height, 3, 3, "zig-diagram-note-box");
                    try self.drawText(sink, .{ .x = box.x + box.width / 2, .top = y + 8, .class = "zig-diagram-note-text", .layout = self.event_text[i] });
                },
                else => {},
            }
        }
        try sink.endGroup();
        try sink.startGroup("zig-diagram-participants");
        for (self.participants, 0..) |part, i| {
            try sink.entity(.{ .kind = .participant, .name = self.diagram.participants.items[part.id].name });
            for ([2]f32{ self.header_bottom_y - part.box_height, self.footer_top_y }) |y| {
                try sink.rect(part.center_x - part.box_width / 2, y, part.box_width, part.box_height, 4, 4, "zig-diagram-node-box");
                try self.drawText(sink, .{ .x = part.center_x, .top = y + (part.box_height - self.participant_text[i].height) / 2, .class = "zig-diagram-label", .layout = self.participant_text[i] });
            }
        }
        try sink.endGroup();
        try sink.endSvg();
    }
};

fn noteBox(parts: []const ParticipantGeometry, note: parser.Note, text: font_mod.TextLayout) NoteBox {
    const first = parts[note.first_participant].center_x;
    var width = @max(140, text.width + 16);
    var x: f32 = first - width / 2;
    if (note.second_participant) |id| {
        const second = parts[id].center_x;
        width = @max(width, @abs(second - first) + 20);
        x = (first + second) / 2 - width / 2;
    } else {
        switch (note.placement) {
            .over => {},
            .left_of => x = first - width - 12,
            .right_of => x = first + 12,
        }
    }
    return .{ .x = x, .width = width, .height = text.height + 16 };
}

test "sequence layout solves positions and produces valid svg" {
    const src =
        \\sequenceDiagram
        \\  autonumber
        \\  title Order Flow
        \\  participant Client
        \\  participant Server
        \\  Client->>+Server: POST /order
        \\  Note over Server: Validate stock
        \\  Server-->>-Client: 200 OK
    ;

    var diag = try parser.parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    var layout = try SequenceLayout.solve(std.testing.allocator, &diag, .{});
    defer layout.deinit(std.testing.allocator);

    try std.testing.expect(layout.total_width > 200.0);
    try std.testing.expect(layout.total_height > 150.0);
    try std.testing.expectEqual(@as(usize, 2), layout.participants.len);

    const svg_out = try layout.renderSvg(std.testing.allocator);
    defer std.testing.allocator.free(svg_out);

    try std.testing.expect(std.mem.indexOf(u8, svg_out, "<svg") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Order Flow") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "POST /order") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zig-diagram-lifeline") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zig-diagram-activation") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "</svg>") != null);
}

test "sequence layout handles self loops and multi-participant notes" {
    const src =
        \\sequenceDiagram
        \\  participant A as Alice
        \\  participant B as Bob
        \\  A->>A: Self processing
        \\  Note left of A: Local state
        \\  Note right of B: Remote state
        \\  Note over A,B: Shared state
        \\  A-xBob: Async fail
        \\  B--)A: Dotted open
    ;

    var diag = try parser.parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    var layout = try SequenceLayout.solve(std.testing.allocator, &diag, .{});
    defer layout.deinit(std.testing.allocator);

    const svg_out = try layout.renderSvg(std.testing.allocator);
    defer std.testing.allocator.free(svg_out);

    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Self processing") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Local state") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Remote state") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Shared state") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "Async fail") != null);
    try std.testing.expect(std.mem.indexOf(u8, svg_out, "zig-diagram-self-arrow") != null);
}
