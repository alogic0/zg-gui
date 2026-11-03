//! Flowchart and graph diagram syntax parser.
//! Supports graph TD/LR/BT/RL, flowchart, shapes, link types, link labels, and subgraphs.
const std = @import("std");

pub const Direction = enum {
    top_to_bottom, // TD, TB
    bottom_to_top, // BT
    left_to_right, // LR
    right_to_left, // RL
};

pub const NodeShape = enum {
    rectangle, // [text]
    rounded_rectangle, // (text)
    stadium, // ([text])
    cylinder, // [(text)]
    circle, // ((text))
    rhombus, // {text}
    hexagon, // {{text}}
    parallelogram, // [/text/]
    trapezoid, // [/text\]
    asymmetric, // >text]
};

pub const LinkStroke = enum {
    solid,
    dotted,
    thick,
};

pub const ArrowHead = enum {
    none,
    arrow,
    circle,
    cross,
};

pub const Link = struct {
    from: u32,
    to: u32,
    stroke: LinkStroke,
    head: ArrowHead,
    text: []const u8,
};

pub const Node = struct {
    id: u32,
    id_name: []const u8,
    label: []const u8,
    shape: NodeShape = .rectangle,
    subgraph_id: ?u32 = null,
};

pub const Subgraph = struct {
    id: u32,
    name: []const u8,
    title: []const u8,
};

pub const FlowchartDiagram = struct {
    direction: Direction = .top_to_bottom,
    nodes: std.ArrayList(Node),
    links: std.ArrayList(Link),
    subgraphs: std.ArrayList(Subgraph),

    pub fn init() FlowchartDiagram {
        return .{
            .direction = .top_to_bottom,
            .nodes = .empty,
            .links = .empty,
            .subgraphs = .empty,
        };
    }

    pub fn deinit(self: *FlowchartDiagram, allocator: std.mem.Allocator) void {
        self.nodes.deinit(allocator);
        self.links.deinit(allocator);
        self.subgraphs.deinit(allocator);
    }

    pub fn findNodeByName(self: *const FlowchartDiagram, name: []const u8) ?u32 {
        for (self.nodes.items, 0..) |n, i| {
            if (std.mem.eql(u8, n.id_name, name)) {
                return @intCast(i);
            }
        }
        return null;
    }

    pub fn getOrAddNode(
        self: *FlowchartDiagram,
        allocator: std.mem.Allocator,
        name: []const u8,
        label: ?[]const u8,
        shape: ?NodeShape,
        cur_subgraph: ?u32,
    ) !u32 {
        if (self.findNodeByName(name)) |existing_idx| {
            if (label) |lbl| {
                self.nodes.items[existing_idx].label = lbl;
            }
            if (shape) |shp| {
                self.nodes.items[existing_idx].shape = shp;
            }
            if (cur_subgraph) |sg| {
                self.nodes.items[existing_idx].subgraph_id = sg;
            }
            return existing_idx;
        }

        const id: u32 = @intCast(self.nodes.items.len);
        try self.nodes.append(allocator, .{
            .id = id,
            .id_name = name,
            .label = label orelse name,
            .shape = shape orelse .rectangle,
            .subgraph_id = cur_subgraph,
        });
        return id;
    }
};

const ParsedNodeRef = struct {
    name: []const u8,
    label: ?[]const u8,
    shape: ?NodeShape,
    rest: []const u8,
};

fn stripQuotes(str: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, str, " \t\r\n");
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return trimmed[1 .. trimmed.len - 1];
    }
    return trimmed;
}

fn findClosingDelimiter(content: []const u8, close_delim: []const u8) ?usize {
    var in_quote = false;
    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '"') {
            in_quote = !in_quote;
            i += 1;
            continue;
        }
        if (!in_quote) {
            if (std.mem.startsWith(u8, content[i..], close_delim)) {
                return i;
            }
        }
        i += 1;
    }
    return null;
}

fn parseNodeRef(input: []const u8) ?ParsedNodeRef {
    const s = std.mem.trimStart(u8, input, " \t");
    if (s.len == 0) return null;

    // Find id boundary
    var id_end: usize = 0;
    while (id_end < s.len) : (id_end += 1) {
        const c = s[id_end];
        if (c == '[' or c == '(' or c == '{' or c == '>' or
            c == ' ' or c == '\t' or c == '-' or c == '=' or
            c == '.' or c == ':' or c == ';' or c == '|')
        {
            break;
        }
    }

    if (id_end == 0) return null;
    const name = s[0..id_end];
    var rem = s[id_end..];

    var label: ?[]const u8 = null;
    var shape: ?NodeShape = null;

    // Check for shape delimiters right after name or after optional whitespace
    const rem_trimmed = std.mem.trimStart(u8, rem, " \t");

    if (std.mem.startsWith(u8, rem_trimmed, "([")) {
        if (findClosingDelimiter(rem_trimmed[2..], "])")) |pos| {
            shape = .stadium;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "[(")) {
        if (findClosingDelimiter(rem_trimmed[2..], ")]")) |pos| {
            shape = .cylinder;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "((")) {
        if (findClosingDelimiter(rem_trimmed[2..], "))")) |pos| {
            shape = .circle;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "{{")) {
        if (findClosingDelimiter(rem_trimmed[2..], "}}")) |pos| {
            shape = .hexagon;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "[/")) {
        if (findClosingDelimiter(rem_trimmed[2..], "/]")) |pos| {
            shape = .parallelogram;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        } else if (findClosingDelimiter(rem_trimmed[2..], "\\]")) |pos| {
            shape = .trapezoid;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "[\\")) {
        if (findClosingDelimiter(rem_trimmed[2..], "\\]")) |pos| {
            shape = .parallelogram;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        } else if (findClosingDelimiter(rem_trimmed[2..], "/]")) |pos| {
            shape = .trapezoid;
            label = stripQuotes(rem_trimmed[2 .. 2 + pos]);
            rem = rem_trimmed[2 + pos + 2 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "[")) {
        if (findClosingDelimiter(rem_trimmed[1..], "]")) |pos| {
            shape = .rectangle;
            label = stripQuotes(rem_trimmed[1 .. 1 + pos]);
            rem = rem_trimmed[1 + pos + 1 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "(")) {
        if (findClosingDelimiter(rem_trimmed[1..], ")")) |pos| {
            shape = .rounded_rectangle;
            label = stripQuotes(rem_trimmed[1 .. 1 + pos]);
            rem = rem_trimmed[1 + pos + 1 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, "{")) {
        if (findClosingDelimiter(rem_trimmed[1..], "}")) |pos| {
            shape = .rhombus;
            label = stripQuotes(rem_trimmed[1 .. 1 + pos]);
            rem = rem_trimmed[1 + pos + 1 ..];
        }
    } else if (std.mem.startsWith(u8, rem_trimmed, ">")) {
        if (findClosingDelimiter(rem_trimmed[1..], "]")) |pos| {
            shape = .asymmetric;
            label = stripQuotes(rem_trimmed[1 .. 1 + pos]);
            rem = rem_trimmed[1 + pos + 1 ..];
        }
    }

    // Skip class annotations like :::className
    const rem_class = std.mem.trimStart(u8, rem, " \t");
    if (std.mem.startsWith(u8, rem_class, ":::")) {
        var c_end: usize = 3;
        while (c_end < rem_class.len and rem_class[c_end] != ' ' and rem_class[c_end] != '\t' and
            rem_class[c_end] != '-' and rem_class[c_end] != '=' and rem_class[c_end] != '.') : (c_end += 1) {}
        rem = rem_class[c_end..];
    }

    return .{
        .name = name,
        .label = label,
        .shape = shape,
        .rest = rem,
    };
}

const ParsedLink = struct {
    stroke: LinkStroke,
    head: ArrowHead,
    text: []const u8,
    rest: []const u8,
};

fn parseLink(input: []const u8) ?ParsedLink {
    var s = std.mem.trimStart(u8, input, " \t");
    if (s.len == 0) return null;

    // Pattern 1: Inline text style
    // A -- text --> B
    // A -- text --- B
    // A -. text .-> B
    // A == text ==> B
    if (std.mem.startsWith(u8, s, "--") and !std.mem.startsWith(u8, s, "-->") and !std.mem.startsWith(u8, s, "---") and !std.mem.startsWith(u8, s, "--o") and !std.mem.startsWith(u8, s, "--x")) {
        const after_prefix = s[2..];
        if (std.mem.indexOf(u8, after_prefix, "-->")) |pos| {
            const txt = stripQuotes(after_prefix[0..pos]);
            return .{
                .stroke = .solid,
                .head = .arrow,
                .text = txt,
                .rest = after_prefix[pos + 3 ..],
            };
        } else if (std.mem.indexOf(u8, after_prefix, "---")) |pos| {
            const txt = stripQuotes(after_prefix[0..pos]);
            return .{
                .stroke = .solid,
                .head = .none,
                .text = txt,
                .rest = after_prefix[pos + 3 ..],
            };
        }
    }

    if (std.mem.startsWith(u8, s, "-.") and !std.mem.startsWith(u8, s, "-.->") and !std.mem.startsWith(u8, s, "-.-")) {
        const after_prefix = s[2..];
        if (std.mem.indexOf(u8, after_prefix, ".->")) |pos| {
            const txt = stripQuotes(after_prefix[0..pos]);
            return .{
                .stroke = .dotted,
                .head = .arrow,
                .text = txt,
                .rest = after_prefix[pos + 3 ..],
            };
        } else if (std.mem.indexOf(u8, after_prefix, ".-")) |pos| {
            const txt = stripQuotes(after_prefix[0..pos]);
            return .{
                .stroke = .dotted,
                .head = .none,
                .text = txt,
                .rest = after_prefix[pos + 2 ..],
            };
        }
    }

    if (std.mem.startsWith(u8, s, "==") and !std.mem.startsWith(u8, s, "==>") and !std.mem.startsWith(u8, s, "===")) {
        const after_prefix = s[2..];
        if (std.mem.indexOf(u8, after_prefix, "==>")) |pos| {
            const txt = stripQuotes(after_prefix[0..pos]);
            return .{
                .stroke = .thick,
                .head = .arrow,
                .text = txt,
                .rest = after_prefix[pos + 3 ..],
            };
        } else if (std.mem.indexOf(u8, after_prefix, "===")) |pos| {
            const txt = stripQuotes(after_prefix[0..pos]);
            return .{
                .stroke = .thick,
                .head = .none,
                .text = txt,
                .rest = after_prefix[pos + 3 ..],
            };
        }
    }

    // Pattern 2: Operator style, optionally followed by |text|
    var stroke: LinkStroke = .solid;
    var head: ArrowHead = .none;
    var op_len: usize = 0;

    if (std.mem.startsWith(u8, s, "-.->")) {
        stroke = .dotted;
        head = .arrow;
        op_len = 4;
    } else if (std.mem.startsWith(u8, s, "-.-")) {
        stroke = .dotted;
        head = .none;
        op_len = 3;
    } else if (std.mem.startsWith(u8, s, "==>")) {
        stroke = .thick;
        head = .arrow;
        op_len = 3;
    } else if (std.mem.startsWith(u8, s, "===")) {
        stroke = .thick;
        head = .none;
        op_len = 3;
    } else if (std.mem.startsWith(u8, s, "-->")) {
        stroke = .solid;
        head = .arrow;
        op_len = 3;
    } else if (std.mem.startsWith(u8, s, "---")) {
        stroke = .solid;
        head = .none;
        op_len = 3;
    } else if (std.mem.startsWith(u8, s, "--o")) {
        stroke = .solid;
        head = .circle;
        op_len = 3;
    } else if (std.mem.startsWith(u8, s, "--x")) {
        stroke = .solid;
        head = .cross;
        op_len = 3;
    } else {
        return null;
    }

    s = s[op_len..];

    // Check for pipe label |text|
    var txt: []const u8 = "";
    const s_pipe = std.mem.trimStart(u8, s, " \t");
    if (std.mem.startsWith(u8, s_pipe, "|")) {
        if (std.mem.indexOf(u8, s_pipe[1..], "|")) |pos| {
            txt = stripQuotes(s_pipe[1 .. 1 + pos]);
            s = s_pipe[1 + pos + 1 ..];
        }
    }

    return .{
        .stroke = stroke,
        .head = head,
        .text = txt,
        .rest = s,
    };
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !FlowchartDiagram {
    var diag = FlowchartDiagram.init();
    errdefer diag.deinit(allocator);

    var cur_subgraph: ?u32 = null;
    var lines = std.mem.splitScalar(u8, input, '\n');

    while (lines.next()) |raw_line| {
        var line = std.mem.trim(u8, raw_line, " \t\r");

        // Strip comments
        if (std.mem.indexOf(u8, line, "%%")) |comment_idx| {
            line = std.mem.trim(u8, line[0..comment_idx], " \t\r");
        }
        if (line.len == 0) continue;

        // Header detection
        if (std.mem.startsWith(u8, line, "graph ") or std.mem.startsWith(u8, line, "flowchart ")) {
            const dir_str = std.mem.trim(u8, line[if (std.mem.startsWith(u8, line, "graph ")) 6 else 10 ..], " \t\r");
            if (std.mem.eql(u8, dir_str, "TD") or std.mem.eql(u8, dir_str, "TB")) {
                diag.direction = .top_to_bottom;
            } else if (std.mem.eql(u8, dir_str, "BT")) {
                diag.direction = .bottom_to_top;
            } else if (std.mem.eql(u8, dir_str, "LR")) {
                diag.direction = .left_to_right;
            } else if (std.mem.eql(u8, dir_str, "RL")) {
                diag.direction = .right_to_left;
            }
            continue;
        }

        // Subgraph handling
        if (std.mem.startsWith(u8, line, "subgraph ")) {
            const rest = std.mem.trim(u8, line[9..], " \t\r");
            var sg_name: []const u8 = rest;
            var sg_title: []const u8 = rest;

            if (parseNodeRef(rest)) |pnr| {
                sg_name = pnr.name;
                sg_title = pnr.label orelse pnr.name;
            }

            const sg_id: u32 = @intCast(diag.subgraphs.items.len);
            try diag.subgraphs.append(allocator, .{
                .id = sg_id,
                .name = sg_name,
                .title = sg_title,
            });
            cur_subgraph = sg_id;
            continue;
        }

        if (std.mem.eql(u8, line, "end")) {
            cur_subgraph = null;
            continue;
        }

        // Parse chained statements: Node Link Node Link Node ...
        var cursor = line;
        var prev_node_id: ?u32 = null;

        while (cursor.len > 0) {
            cursor = std.mem.trimStart(u8, cursor, " \t;");
            if (cursor.len == 0) break;

            if (prev_node_id) |from_id| {
                // Expect link or end
                if (parseLink(cursor)) |plink| {
                    cursor = std.mem.trimStart(u8, plink.rest, " \t");
                    if (parseNodeRef(cursor)) |pnode| {
                        const to_id = try diag.getOrAddNode(
                            allocator,
                            pnode.name,
                            pnode.label,
                            pnode.shape,
                            cur_subgraph,
                        );

                        try diag.links.append(allocator, .{
                            .from = from_id,
                            .to = to_id,
                            .stroke = plink.stroke,
                            .head = plink.head,
                            .text = plink.text,
                        });

                        prev_node_id = to_id;
                        cursor = pnode.rest;
                        continue;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            } else {
                // Expect first node
                if (parseNodeRef(cursor)) |pnode| {
                    const node_id = try diag.getOrAddNode(
                        allocator,
                        pnode.name,
                        pnode.label,
                        pnode.shape,
                        cur_subgraph,
                    );
                    prev_node_id = node_id;
                    cursor = pnode.rest;
                } else {
                    break;
                }
            }
        }
    }

    return diag;
}

test "flowchart parser basic graph with shapes and link labels" {
    const src =
        \\graph TD
        \\  A[Start Process] -->|init| B{Is Ready?}
        \\  B -->|Yes| C([Proceed])
        \\  B -. No .-> D[(Backup DB)]
        \\  C ==> E((Success))
        \\  D --- E
    ;

    var diag = try parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    try std.testing.expectEqual(Direction.top_to_bottom, diag.direction);
    try std.testing.expectEqual(@as(usize, 5), diag.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 5), diag.links.items.len);

    // Node shapes
    try std.testing.expectEqualStrings("Start Process", diag.nodes.items[0].label);
    try std.testing.expectEqual(NodeShape.rectangle, diag.nodes.items[0].shape);

    try std.testing.expectEqualStrings("Is Ready?", diag.nodes.items[1].label);
    try std.testing.expectEqual(NodeShape.rhombus, diag.nodes.items[1].shape);

    try std.testing.expectEqualStrings("Proceed", diag.nodes.items[2].label);
    try std.testing.expectEqual(NodeShape.stadium, diag.nodes.items[2].shape);

    try std.testing.expectEqualStrings("Backup DB", diag.nodes.items[3].label);
    try std.testing.expectEqual(NodeShape.cylinder, diag.nodes.items[3].shape);

    try std.testing.expectEqualStrings("Success", diag.nodes.items[4].label);
    try std.testing.expectEqual(NodeShape.circle, diag.nodes.items[4].shape);

    // Links
    try std.testing.expectEqualStrings("init", diag.links.items[0].text);
    try std.testing.expectEqual(LinkStroke.solid, diag.links.items[0].stroke);
    try std.testing.expectEqual(ArrowHead.arrow, diag.links.items[0].head);

    try std.testing.expectEqualStrings("No", diag.links.items[2].text);
    try std.testing.expectEqual(LinkStroke.dotted, diag.links.items[2].stroke);

    try std.testing.expectEqual(LinkStroke.thick, diag.links.items[3].stroke);
    try std.testing.expectEqual(LinkStroke.solid, diag.links.items[4].stroke);
    try std.testing.expectEqual(ArrowHead.none, diag.links.items[4].head);
}

test "flowchart parser chained links and subgraphs" {
    const src =
        \\flowchart LR
        \\  subgraph Backend [Server Cluster]
        \\    S1 --> S2 --> S3
        \\  end
        \\  Client --> S1
    ;

    var diag = try parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    try std.testing.expectEqual(Direction.left_to_right, diag.direction);
    try std.testing.expectEqual(@as(usize, 1), diag.subgraphs.items.len);
    try std.testing.expectEqualStrings("Server Cluster", diag.subgraphs.items[0].title);

    try std.testing.expectEqual(@as(usize, 4), diag.nodes.items.len);
    // S1, S2, S3 should have subgraph_id == 0
    try std.testing.expectEqual(@as(?u32, 0), diag.nodes.items[0].subgraph_id);
    try std.testing.expectEqual(@as(?u32, 0), diag.nodes.items[1].subgraph_id);
    try std.testing.expectEqual(@as(?u32, 0), diag.nodes.items[2].subgraph_id);
    // Client should have subgraph_id == null
    try std.testing.expectEqual(@as(?u32, null), diag.nodes.items[3].subgraph_id);

    // Links: S1->S2, S2->S3, Client->S1
    try std.testing.expectEqual(@as(usize, 3), diag.links.items.len);
}

test "flowchart parser advanced shapes, directions, and quotes" {
    const src =
        \\graph RL
        \\  %% Leading comment
        \\  H{{Hexagon Shape}} --> P[/Parallelogram/]
        \\  P --> T[/Trapezoid Shape\]
        \\  T --> A>Banner Flag]
        \\  A --> Q["Quoted Label with (special) [chars]"]
        \\  Q --o H
        \\  Q --x T
    ;

    var diag = try parse(std.testing.allocator, src);
    defer diag.deinit(std.testing.allocator);

    try std.testing.expectEqual(Direction.right_to_left, diag.direction);
    try std.testing.expectEqual(@as(usize, 5), diag.nodes.items.len);

    try std.testing.expectEqual(NodeShape.hexagon, diag.nodes.items[0].shape);
    try std.testing.expectEqualStrings("Hexagon Shape", diag.nodes.items[0].label);

    try std.testing.expectEqual(NodeShape.parallelogram, diag.nodes.items[1].shape);
    try std.testing.expectEqualStrings("Parallelogram", diag.nodes.items[1].label);

    try std.testing.expectEqual(NodeShape.trapezoid, diag.nodes.items[2].shape);
    try std.testing.expectEqualStrings("Trapezoid Shape", diag.nodes.items[2].label);

    try std.testing.expectEqual(NodeShape.asymmetric, diag.nodes.items[3].shape);
    try std.testing.expectEqualStrings("Banner Flag", diag.nodes.items[3].label);

    try std.testing.expectEqualStrings("Quoted Label with (special) [chars]", diag.nodes.items[4].label);

    // Endings --o and --x
    try std.testing.expectEqual(ArrowHead.circle, diag.links.items[4].head);
    try std.testing.expectEqual(ArrowHead.cross, diag.links.items[5].head);
}
