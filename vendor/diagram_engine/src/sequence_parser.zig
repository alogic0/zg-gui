//! Sequence diagram syntax parser.
//! Parses sequence diagrams into structured event streams.
const std = @import("std");

pub const MessageType = enum {
    solid_arrow, // ->> (synchronous)
    dotted_arrow, // -->> (reply)
    solid_open, // -> (plain)
    dotted_open, // --> (dotted plain)
    solid_cross, // -x (lost)
    dotted_cross, // --x (dotted lost)
    solid_async, // -) (async)
    dotted_async, // --) (dotted async)
};

pub const NotePlacement = enum {
    left_of,
    right_of,
    over,
};

pub const Participant = struct {
    id: u32,
    name: []const u8,
    label: []const u8,
    is_actor: bool = false,
};

pub const Message = struct {
    from: u32,
    to: u32,
    msg_type: MessageType,
    text: []const u8,
};

pub const Note = struct {
    placement: NotePlacement,
    first_participant: u32,
    second_participant: ?u32 = null,
    text: []const u8,
};

pub const EventKind = enum {
    message,
    activate,
    deactivate,
    note,
};

pub const Event = union(EventKind) {
    message: Message,
    activate: u32,
    deactivate: u32,
    note: Note,
};

pub const SequenceDiagram = struct {
    title: ?[]const u8 = null,
    autonumber: bool = false,
    participants: std.ArrayList(Participant),
    events: std.ArrayList(Event),

    pub fn init() SequenceDiagram {
        return .{
            .participants = std.ArrayList(Participant).empty,
            .events = std.ArrayList(Event).empty,
        };
    }

    pub fn deinit(self: *SequenceDiagram, allocator: std.mem.Allocator) void {
        self.participants.deinit(allocator);
        self.events.deinit(allocator);
    }

    pub fn getOrAddParticipant(
        self: *SequenceDiagram,
        allocator: std.mem.Allocator,
        name: []const u8,
        label: ?[]const u8,
        is_actor: bool,
    ) !u32 {
        const trimmed_name = std.mem.trim(u8, name, " \t\r");
        for (self.participants.items, 0..) |p, i| {
            if (std.mem.eql(u8, p.name, trimmed_name)) {
                return @intCast(i);
            }
        }
        const id: u32 = @intCast(self.participants.items.len);
        try self.participants.append(allocator, .{
            .id = id,
            .name = trimmed_name,
            .label = if (label) |l| std.mem.trim(u8, l, " \t\r") else trimmed_name,
            .is_actor = is_actor,
        });
        return id;
    }
};

pub const ParserError = error{
    InvalidHeader,
    EmptyDiagram,
    InvalidSyntax,
    UnknownParticipant,
    OutOfMemory,
};

pub fn parse(allocator: std.mem.Allocator, source: []const u8) ParserError!SequenceDiagram {
    var diag = SequenceDiagram.init();
    errdefer diag.deinit(allocator);

    var lines = std.mem.splitScalar(u8, source, '\n');
    var found_header = false;

    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r");
        if (line.len == 0 or std.mem.startsWith(u8, line, "%%")) continue;

        if (!found_header) {
            if (std.ascii.eqlIgnoreCase(line, "sequenceDiagram")) {
                found_header = true;
                continue;
            }
            return error.InvalidHeader;
        }

        // Directives
        if (std.ascii.eqlIgnoreCase(line, "autonumber")) {
            diag.autonumber = true;
            continue;
        }

        if (std.mem.startsWith(u8, line, "title ")) {
            diag.title = std.mem.trim(u8, line[6..], " \t\r");
            continue;
        }

        // Participant declaration: "participant A [as Label]" or "actor A [as Label]"
        if (std.mem.startsWith(u8, line, "participant ") or std.mem.startsWith(u8, line, "actor ")) {
            const is_actor = std.mem.startsWith(u8, line, "actor ");
            const rest = if (is_actor) line[6..] else line[12..];
            if (std.mem.indexOf(u8, rest, " as ")) |as_pos| {
                const name = rest[0..as_pos];
                const label = rest[as_pos + 4 ..];
                _ = try diag.getOrAddParticipant(allocator, name, label, is_actor);
            } else {
                _ = try diag.getOrAddParticipant(allocator, rest, null, is_actor);
            }
            continue;
        }

        // Explicit activation / deactivation: "activate A", "deactivate A"
        if (std.mem.startsWith(u8, line, "activate ")) {
            const name = std.mem.trim(u8, line[9..], " \t\r");
            const p = try diag.getOrAddParticipant(allocator, name, null, false);
            try diag.events.append(allocator, .{ .activate = p });
            continue;
        }
        if (std.mem.startsWith(u8, line, "deactivate ")) {
            const name = std.mem.trim(u8, line[11..], " \t\r");
            const p = try diag.getOrAddParticipant(allocator, name, null, false);
            try diag.events.append(allocator, .{ .deactivate = p });
            continue;
        }

        // Notes: "Note left of A: text", "Note right of A: text", "Note over A, B: text"
        if (std.mem.startsWith(u8, line, "Note ") or std.mem.startsWith(u8, line, "note ")) {
            try parseNote(&diag, allocator, line[5..]);
            continue;
        }

        // Messages: "A->>B: text" or "A->>+B: text" or "A->>-B: text"
        if (try parseMessage(&diag, allocator, line)) {
            continue;
        }

        return error.InvalidSyntax;
    }

    if (!found_header) return error.InvalidHeader;
    return diag;
}

fn parseNote(diag: *SequenceDiagram, allocator: std.mem.Allocator, rest: []const u8) !void {
    const colon_pos = std.mem.indexOfScalar(u8, rest, ':') orelse return error.InvalidSyntax;
    const targets = std.mem.trim(u8, rest[0..colon_pos], " \t\r");
    const note_text = std.mem.trim(u8, rest[colon_pos + 1 ..], " \t\r");

    var placement: NotePlacement = .over;
    var participant_part: []const u8 = "";

    if (std.mem.startsWith(u8, targets, "left of ")) {
        placement = .left_of;
        participant_part = targets[8..];
    } else if (std.mem.startsWith(u8, targets, "right of ")) {
        placement = .right_of;
        participant_part = targets[9..];
    } else if (std.mem.startsWith(u8, targets, "over ")) {
        placement = .over;
        participant_part = targets[5..];
    } else {
        return error.InvalidSyntax;
    }

    if (std.mem.indexOfScalar(u8, participant_part, ',')) |comma_pos| {
        const p1_name = participant_part[0..comma_pos];
        const p2_name = participant_part[comma_pos + 1 ..];
        const p1 = try diag.getOrAddParticipant(allocator, p1_name, null, false);
        const p2 = try diag.getOrAddParticipant(allocator, p2_name, null, false);
        try diag.events.append(allocator, .{
            .note = .{
                .placement = placement,
                .first_participant = p1,
                .second_participant = p2,
                .text = note_text,
            },
        });
    } else {
        const p = try diag.getOrAddParticipant(allocator, participant_part, null, false);
        try diag.events.append(allocator, .{
            .note = .{
                .placement = placement,
                .first_participant = p,
                .text = note_text,
            },
        });
    }
}

const ArrowDesc = struct {
    token: []const u8,
    msg_type: MessageType,
};

const arrow_tokens = [_]ArrowDesc{
    .{ .token = "-->>", .msg_type = .dotted_arrow },
    .{ .token = "->>", .msg_type = .solid_arrow },
    .{ .token = "--x", .msg_type = .dotted_cross },
    .{ .token = "-x", .msg_type = .solid_cross },
    .{ .token = "--)", .msg_type = .dotted_async },
    .{ .token = "-)", .msg_type = .solid_async },
    .{ .token = "-->", .msg_type = .dotted_open },
    .{ .token = "->", .msg_type = .solid_open },
};

fn parseMessage(diag: *SequenceDiagram, allocator: std.mem.Allocator, line: []const u8) !bool {
    for (arrow_tokens) |desc| {
        if (std.mem.indexOf(u8, line, desc.token)) |token_pos| {
            const from_name = std.mem.trim(u8, line[0..token_pos], " \t\r");
            if (from_name.len == 0) continue;

            const after_token = line[token_pos + desc.token.len ..];
            var activate_target = false;
            var deactivate_sender = false;
            var target_start: usize = 0;

            if (after_token.len > 0 and after_token[0] == '+') {
                activate_target = true;
                target_start = 1;
            } else if (after_token.len > 0 and after_token[0] == '-') {
                deactivate_sender = true;
                target_start = 1;
            }

            const colon_pos = std.mem.indexOfScalar(u8, after_token, ':');
            const to_end = colon_pos orelse after_token.len;
            const to_name = std.mem.trim(u8, after_token[target_start..to_end], " \t\r");
            if (to_name.len == 0) continue;

            const msg_text = if (colon_pos) |pos| std.mem.trim(u8, after_token[pos + 1 ..], " \t\r") else "";

            const from_id = try diag.getOrAddParticipant(allocator, from_name, null, false);
            const to_id = try diag.getOrAddParticipant(allocator, to_name, null, false);

            try diag.events.append(allocator, .{
                .message = .{
                    .from = from_id,
                    .to = to_id,
                    .msg_type = desc.msg_type,
                    .text = msg_text,
                },
            });

            if (activate_target) {
                try diag.events.append(allocator, .{ .activate = to_id });
            } else if (deactivate_sender) {
                try diag.events.append(allocator, .{ .deactivate = from_id });
            }

            return true;
        }
    }
    return false;
}

test "sequence diagram parser with participants, messages, notes and activations" {
    const src =
        \\sequenceDiagram
        \\  autonumber
        \\  title Simple Checkout
        \\  actor User as Customer
        \\  participant Web as Web App
        \\  participant DB as Database
        \\  User->>+Web: Click Buy
        \\  Note over Web: Validate cart
        \\  Web->>DB: Query inventory
        \\  DB-->>Web: Inventory OK
        \\  Web-->>-User: Show Order Confirmation
    ;

    var diag = try parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    try std.testing.expect(diag.autonumber);
    try std.testing.expectEqualStrings("Simple Checkout", diag.title.?);
    try std.testing.expectEqual(@as(usize, 3), diag.participants.items.len);
    try std.testing.expect(diag.participants.items[0].is_actor);
    try std.testing.expectEqualStrings("Customer", diag.participants.items[0].label);

    // Events:
    // 0: Message User -> Web ("Click Buy")
    // 1: Activate Web
    // 2: Note over Web ("Validate cart")
    // 3: Message Web -> DB ("Query inventory")
    // 4: Message DB -> Web ("Inventory OK")
    // 5: Message Web -> User ("Show Order Confirmation")
    // 6: Deactivate Web
    try std.testing.expectEqual(@as(usize, 7), diag.events.items.len);
    try std.testing.expectEqual(@as(u32, 1), diag.events.items[1].activate);
    try std.testing.expectEqual(@as(u32, 1), diag.events.items[6].deactivate);
}
