//! A bounded synthetic planning workspace using the public template and host APIs.
const std = @import("std");
const gui = @import("zg_gui");
const template = @import("workspace_template");
const P = gui.Projection(template.snapshot_capacity + 1);
const max_tasks = 24;
const max_activity = 5;

fn Text(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = @splat(0),
        len: usize = 0,
        fn from(value: []const u8) @This() {
            var result: @This() = .{};
            if (!result.set(value)) unreachable;
            return result;
        }
        fn set(self: *@This(), value: []const u8) bool {
            if (value.len > capacity or !std.unicode.utf8ValidateSlice(value)) return false;
            @memcpy(self.bytes[0..value.len], value);
            self.len = value.len;
            return true;
        }
        fn slice(self: *const @This()) []const u8 {
            return self.bytes[0..self.len];
        }
    };
}
const Status = enum { planned, active, done };
const Priority = enum { high, medium, low };
const Task = struct {
    id: u32 = 0,
    code: Text(16) = .{},
    title: Text(192) = .{},
    notes: Text(1024) = .{},
    status: Status = .planned,
    priority: Priority = .medium,
    owner: u8 = 0,
};
const Activity = struct {
    id: u32 = 0,
    task: u32 = 0,
    label: []const u8 = "",
    detail: Text(192) = .{},
    time: []const u8 = "Just now",
};
const State = struct {
    tasks: [max_tasks]Task = @splat(.{}),
    len: usize = 0,
    selected: u32 = 3,
    next_id: u32 = 9,
    filter: u8 = 0,
    sort: enum { manual, priority, title } = .manual,
    query: Text(192) = .{},
    dark: bool = false,
    font_size: u8 = 100,
    focus_revision: u32 = 0,
    activity: [max_activity]Activity = @splat(.{}),
    activity_len: usize = 0,
    next_activity: u32 = 1,
    notice: []const u8 = "Sample workspace.",
};
const Action = enum(u32) { select = 1, complete, filter, add, remove, up, down, theme, reset, clear, font_decrease, font_increase };
const Input = enum(u32) { search = 1, title, notes, status, priority, sort, owner };
const owners = [_][]const u8{ "Alex Kim", "Jules Lee", "Morgan Reed" };
const initials = [_][]const u8{ "AK", "JL", "MR" };

var state = State{};
var snapshot = P.Snapshot{};
var exchange: [2048]u8 = undefined;
var scratch: [131072]u8 = undefined;
var output: [131072]u8 = undefined;
var output_len: usize = 0;
var mode: gui.patch.RenderMode = .full;
// Example-specific, versioned snapshot; never expose raw State bytes or pointers.
var session_buffer: [32768]u8 = undefined;
var session_prepared = false;
var mounted = false;

fn seed() State {
    var s = State{};
    const titles = [_][]const u8{
        "Map the site structure",       "Define the visual direction",     "Build the component library",
        "Design the landing page",      "Write the product story",         "Connect the contact form",
        "Check keyboard accessibility", "Gather inspiration & references",
    };
    const statuses = [_]Status{ .done, .done, .active, .active, .planned, .planned, .active, .done };
    for (titles, 0..) |title, i| {
        var code: [16]u8 = undefined;
        s.tasks[i] = .{
            .id = @intCast(i + 1),
            .code = Text(16).from(std.fmt.bufPrint(&code, "FW-{d}", .{101 + i}) catch unreachable),
            .title = Text(192).from(title),
            .notes = Text(1024).from(if (i == 2) "Bring the foundations together: buttons, form fields, and cards. Keep the components small and make every state feel considered.\n\nStart with the pieces we use on the landing page." else "A small step toward a thoughtful, accessible project. Add your notes here."),
            .status = statuses[i],
            .priority = if (i == 2 or i == 3 or i == 6) .high else if (i == 7) .low else .medium,
            .owner = @intCast(i % 3),
        };
    }
    s.len = titles.len;
    s.activity[0] = .{ .id = 1, .task = 3, .label = "Started a task", .detail = Text(192).from(titles[2]), .time = "Sample · 10:24" };
    s.activity[1] = .{ .id = 2, .task = 2, .label = "Completed a task", .detail = Text(192).from(titles[1]), .time = "Sample · 09:48" };
    s.activity[2] = .{ .id = 3, .task = 1, .label = "Completed a task", .detail = Text(192).from(titles[0]), .time = "Sample · 09:12" };
    s.activity_len = 3;
    s.next_activity = 4;
    return s;
}
fn indexOf(s: *const State, id: u32) ?usize {
    for (s.tasks[0..s.len], 0..) |task, i| if (task.id == id) return i;
    return null;
}
fn log(s: *State, input: struct { task: *const Task, label: []const u8 }) void {
    if (s.activity_len > 0 and s.activity[0].task == input.task.id and std.mem.eql(u8, s.activity[0].label, input.label)) {
        s.activity[0].detail = input.task.title;
        return;
    }
    const last = @min(s.activity_len, max_activity - 1);
    var i = last;
    while (i > 0) : (i -= 1) s.activity[i] = s.activity[i - 1];
    s.activity[0] = .{ .id = s.next_activity, .task = input.task.id, .label = input.label, .detail = input.task.title };
    // Compact bounded keys stay safely inside the generated node namespace.
    s.next_activity = if (s.next_activity == 10000) 1 else s.next_activity + 1;
    s.activity_len = @min(max_activity, s.activity_len + 1);
}
fn matches(s: *const State, task: *const Task) bool {
    if (s.filter != 0 and @backingInt(task.status) + 1 != s.filter) return false;
    return s.query.len == 0 or std.ascii.findIgnoreCase(task.title.slice(), s.query.slice()) != null or std.ascii.findIgnoreCase(task.code.slice(), s.query.slice()) != null;
}
fn statusLabel(status: Status) []const u8 {
    return switch (status) {
        .planned => "To do",
        .active => "In progress",
        .done => "Done",
    };
}
fn priorityLabel(priority: Priority) []const u8 {
    return switch (priority) {
        .high => "High",
        .medium => "Medium",
        .low => "Low",
    };
}
const Metric = struct {
    label: []const u8,
    value: []const u8,
    note: []const u8,
    icon: []const u8,
    progress: struct { @"--progress": gui.template.StyleValue },
    show_progress: bool = false,
    show_chart: bool = false,
    chart_label: []const u8 = "",
    chart: struct { planned_y: u32 = 24, planned_height: u32 = 0, active_y: u32 = 24, active_height: u32 = 0, done_y: u32 = 24, done_height: u32 = 0 } = .{},
};
const Row = struct {
    id: u32,
    code: []const u8,
    title: []const u8,
    status: []const u8,
    status_label: []const u8,
    priority: []const u8,
    priority_label: []const u8,
    owner: []const u8,
    initials: []const u8,
    selected: bool,
    done: bool,
    toggle_label: []const u8,
};
const ActivityView = struct { id: u32, label: []const u8, detail: []const u8, time: []const u8 };

fn render(input: struct { candidate: State, mode: gui.patch.RenderMode }) u32 {
    const s = &input.candidate;
    var rows: [max_tasks]Row = undefined;
    var indices: [max_tasks]usize = undefined;
    var count: usize = 0;
    var counts = [_]usize{ 0, 0, 0 };
    for (s.tasks[0..s.len], 0..) |*task, i| {
        counts[@backingInt(task.status)] += 1;
        if (matches(s, task)) {
            indices[count] = i;
            count += 1;
        }
    }
    // A bounded stable insertion sort keeps equal-priority rows in manual order.
    if (s.sort != .manual) for (1..@max(count, 1)) |i| {
        var j = i;
        while (j > 0) : (j -= 1) {
            const a = &s.tasks[indices[j - 1]];
            const b = &s.tasks[indices[j]];
            const before = if (s.sort == .priority) @backingInt(b.priority) < @backingInt(a.priority) else std.ascii.orderIgnoreCase(b.title.slice(), a.title.slice()) == .lt;
            if (!before) break;
            std.mem.swap(usize, &indices[j - 1], &indices[j]);
        }
    };
    for (indices[0..count], 0..) |index, i| {
        const task = &s.tasks[index];
        rows[i] = .{
            .id = task.id,
            .code = task.code.slice(),
            .title = task.title.slice(),
            .status = @tagName(task.status),
            .status_label = statusLabel(task.status),
            .priority = @tagName(task.priority),
            .priority_label = priorityLabel(task.priority),
            .owner = owners[task.owner],
            .initials = initials[task.owner],
            .selected = task.id == s.selected,
            .done = task.status == .done,
            .toggle_label = if (task.status == .done) "Reopen task" else "Complete task",
        };
    }
    var activity: [max_activity]ActivityView = undefined;
    for (s.activity[0..s.activity_len], 0..) |*item, i| activity[i] = .{ .id = item.id, .label = item.label, .detail = item.detail.slice(), .time = item.time };
    const selected_index = indexOf(s, s.selected);
    const empty_task = Task{};
    const selected = if (selected_index) |i| &s.tasks[i] else &empty_task;
    const percent = if (s.len == 0) 0 else (counts[2] * 100 + s.len / 2) / s.len;
    var font_size_label: [4]u8 = undefined;
    var progress_value: [32]u8 = undefined;
    var progress_note: [64]u8 = undefined;
    var active_value: [32]u8 = undefined;
    var planned_value: [32]u8 = undefined;
    var row_count: [48]u8 = undefined;
    var chart_label: [96]u8 = undefined;
    const peak = @max(1, @max(counts[0], @max(counts[1], counts[2])));
    const planned_height: u32 = @intCast(counts[0] * 24 / peak);
    const active_height: u32 = @intCast(counts[1] * 24 / peak);
    const done_height: u32 = @intCast(counts[2] * 24 / peak);
    const progress: @FieldType(Metric, "progress") = .{ .@"--progress" = gui.template.StyleValue{ .value = @intCast(percent), .unit = .percent } };
    var next = P.Snapshot{};
    var html = gui.html.Writer{ .buffer = &scratch };
    var stream = gui.html.Writer{ .buffer = &output };
    var patches = gui.patch.Writer{ .output = &stream };
    var p = P{ .html = &html, .next = &next, .previous = if (input.mode == .patch) &snapshot else null, .patches = if (input.mode == .patch) &patches else null, .writing = input.mode == .full };
    template.project(&p, .{
        .theme = @as([]const u8, if (s.dark) "dark" else "light"),
        .theme_label = @as([]const u8, if (s.dark) "Use light theme" else "Use dark theme"),
        .theme_button = @as([]const u8, if (s.dark) "Light theme" else "Dark theme"),
        .dark = s.dark,
        .font_style = .{ .@"--font-scale" = s.font_size },
        .font_size_label = std.fmt.bufPrint(&font_size_label, "{d}%", .{s.font_size}) catch unreachable,
        .font_decrease_disabled = s.font_size <= 80,
        .font_increase_disabled = s.font_size >= 140,
        .notice = s.notice,
        .query = s.query.slice(),
        .sort = @tagName(s.sort),
        .add_disabled = s.len >= max_tasks or s.next_id >= 10000,
        .up_disabled = selected_index == null or selected_index.? == 0,
        .down_disabled = selected_index == null or selected_index.? + 1 >= s.len,
        .all_active = s.filter == 0,
        .planned_active = s.filter == 1,
        .progress_active = s.filter == 2,
        .done_active = s.filter == 3,
        .total = s.len,
        .rows = rows[0..count],
        .empty = count == 0,
        .row_count = std.fmt.bufPrint(&row_count, "{d} of {d} tasks", .{ count, s.len }) catch unreachable,
        .metric_progress = Metric{ .label = "Progress", .value = std.fmt.bufPrint(&progress_value, "{d}%", .{percent}) catch unreachable, .note = std.fmt.bufPrint(&progress_note, "{d} of {d} tasks complete", .{ counts[2], s.len }) catch unreachable, .icon = "workspace-icons.svg#progress", .progress = progress, .show_progress = true },
        .metric_active = Metric{
            .label = "Active",
            .value = std.fmt.bufPrint(&active_value, "{d}", .{counts[1]}) catch unreachable,
            .note = "Good things are taking shape",
            .icon = "workspace-icons.svg#layers",
            .progress = progress,
            .show_chart = true,
            .chart_label = std.fmt.bufPrint(&chart_label, "{d} to do, {d} in progress, {d} done", .{ counts[0], counts[1], counts[2] }) catch unreachable,
            .chart = .{ .planned_y = 24 - planned_height, .planned_height = planned_height, .active_y = 24 - active_height, .active_height = active_height, .done_y = 24 - done_height, .done_height = done_height },
        },
        .metric_planned = Metric{ .label = "To do", .value = std.fmt.bufPrint(&planned_value, "{d}", .{counts[0]}) catch unreachable, .note = "Ready when you are", .icon = "workspace-icons.svg#arrow", .progress = progress },
        .has_selection = selected_index != null,
        .no_selection = selected_index == null,
        .selected_code = selected.code.slice(),
        .selected_title = selected.title.slice(),
        .selected_notes = selected.notes.slice(),
        .selected_status = @tagName(selected.status),
        .selected_priority = @tagName(selected.priority),
        .selected_owner_value = @as([]const u8, switch (selected.owner) {
            0 => "0",
            1 => "1",
            else => "2",
        }),
        .activity = activity[0..s.activity_len],
        .actions = .{ .select = Action.select, .complete = Action.complete, .filter = Action.filter, .add = Action.add, .remove = Action.remove, .up = Action.up, .down = Action.down, .theme = Action.theme, .reset = Action.reset, .clear = Action.clear, .font_decrease = Action.font_decrease, .font_increase = Action.font_increase },
        .inputs = .{ .search = Input.search, .title = Input.title, .notes = Input.notes, .status = Input.status, .priority = Input.priority, .sort = Input.sort, .owner = Input.owner },
    });
    p.focus(.{ .owner = template.nodes.detail_title, .target = if (selected_index != null) template.nodes.detail_title else template.nodes.add_task, .revision = s.focus_revision });
    if (html.failed or stream.failed) {
        output_len = 0;
        mode = .patch;
        return 0;
    }
    if (input.mode == .full) {
        @memcpy(output[0..html.len], html.slice());
        output_len = html.len;
    } else output_len = stream.len;
    state = input.candidate;
    snapshot = next;
    mode = input.mode;
    return @intCast(output_len);
}

pub export fn init() u32 {
    const candidate = if (session_prepared) state else seed();
    session_prepared = false;
    mounted = true;
    return render(.{ .candidate = candidate, .mode = .full });
}
pub export fn resync() u32 {
    return render(.{ .candidate = state, .mode = .full });
}
pub export fn dispatch(action_id: u32, value: i32) u32 {
    var next = state;
    const action = std.enums.fromInt(Action, action_id) orelse return render(.{ .candidate = next, .mode = .patch });
    switch (action) {
        .select => if (value > 0 and indexOf(&next, @intCast(value)) != null) {
            next.selected = @intCast(value);
            next.focus_revision +|= 1;
        },
        .complete => if (value > 0) {
            if (indexOf(&next, @intCast(value))) |i| {
                next.tasks[i].status = if (next.tasks[i].status == .done) .planned else .done;
                log(&next, .{ .task = &next.tasks[i], .label = if (next.tasks[i].status == .done) "Completed a task" else "Reopened a task" });
                next.notice = "Task updated.";
            }
        },
        .filter => if (value >= 0 and value <= 3) {
            next.filter = @intCast(value);
        },
        .add => if (next.len < max_tasks and next.next_id < 10000) {
            var code: [16]u8 = undefined;
            next.tasks[next.len] = .{ .id = next.next_id, .code = Text(16).from(std.fmt.bufPrint(&code, "FW-{d}", .{100 + next.next_id}) catch unreachable), .title = Text(192).from("Untitled task") };
            next.selected = next.next_id;
            next.focus_revision +|= 1;
            next.next_id += 1;
            next.len += 1;
            next.filter = 0;
            next.query = .{};
            next.sort = .manual;
            log(&next, .{ .task = &next.tasks[next.len - 1], .label = "Created a task" });
            next.notice = if (next.len == max_tasks) "All 24 task slots are in use. Delete a task to add another." else "Task added. Edit its details in the task panel.";
        },
        .remove => if (indexOf(&next, next.selected)) |i| {
            log(&next, .{ .task = &next.tasks[i], .label = "Removed a task" });
            for (i..next.len - 1) |j| next.tasks[j] = next.tasks[j + 1];
            next.len -= 1;
            next.selected = if (next.len == 0) 0 else next.tasks[@min(i, next.len - 1)].id;
            next.focus_revision +|= 1;
            next.notice = "Task removed. Reset the demo to restore the sample.";
        },
        .up, .down => if (indexOf(&next, next.selected)) |i| {
            const other = if (action == .up) i -| 1 else @min(i + 1, next.len - 1);
            if (other != i) {
                std.mem.swap(Task, &next.tasks[i], &next.tasks[other]);
                next.sort = .manual;
                next.notice = "Task moved. You’re back in manual order.";
            }
        },
        .font_decrease => next.font_size = @max(80, next.font_size - 10),
        .font_increase => next.font_size = @min(140, next.font_size + 10),
        .theme => next.dark = !next.dark,
        .reset => {
            const dark = next.dark;
            const font_size = next.font_size;
            next = seed();
            next.dark = dark;
            next.font_size = font_size;
            next.notice = "Sample workspace restored.";
        },
        .clear => {
            next.filter = 0;
            next.query = .{};
        },
    }
    return render(.{ .candidate = next, .mode = .patch });
}
pub export fn setInput(kind_id: u32, length: u32) u32 {
    var next = state;
    const kind = std.enums.fromInt(Input, kind_id) orelse return render(.{ .candidate = next, .mode = .patch });
    if (length > exchange.len or !std.unicode.utf8ValidateSlice(exchange[0..@min(length, exchange.len)])) return render(.{ .candidate = next, .mode = .patch });
    const value = exchange[0..length];
    switch (kind) {
        .search => {
            _ = next.query.set(value);
        },
        .sort => {
            if (std.meta.stringToEnum(@TypeOf(next.sort), value)) |v| next.sort = v;
        },
        else => if (indexOf(&next, next.selected)) |i| {
            const task = &next.tasks[i];
            switch (kind) {
                .title => {
                    if (!task.title.set(value)) return render(.{ .candidate = state, .mode = .patch });
                },
                .notes => {
                    if (!task.notes.set(value)) return render(.{ .candidate = state, .mode = .patch });
                },
                .status => task.status = std.meta.stringToEnum(Status, value) orelse return render(.{ .candidate = state, .mode = .patch }),
                .priority => task.priority = std.meta.stringToEnum(Priority, value) orelse return render(.{ .candidate = state, .mode = .patch }),
                .owner => {
                    const owner = std.fmt.parseInt(u8, value, 10) catch return render(.{ .candidate = state, .mode = .patch });
                    if (owner >= owners.len) return render(.{ .candidate = state, .mode = .patch });
                    task.owner = owner;
                },
                else => unreachable,
            }
            log(&next, .{ .task = task, .label = "Updated task details" });
            next.notice = "Task updated.";
        },
    }
    return render(.{ .candidate = next, .mode = .patch });
}
pub export fn getRenderBuffer() usize {
    return @intFromPtr(&output);
}
pub export fn getRenderLength() u32 {
    return @intCast(output_len);
}
pub export fn getRenderMode() u32 {
    return @backingInt(mode);
}
pub export fn getExchangeBuffer() usize {
    return @intFromPtr(&exchange);
}
pub export fn getExchangeCapacity() u32 {
    return exchange.len;
}

// Session hooks belong to this example, not the framework mount ABI.
const activity_labels = [_][]const u8{ "Started a task", "Completed a task", "Reopened a task", "Created a task", "Removed a task", "Updated task details" };
const activity_times = [_][]const u8{ "Just now", "Sample · 10:24", "Sample · 09:48", "Sample · 09:12" };
fn stringIndex(values: []const []const u8, value: []const u8) !u8 {
    for (values, 0..) |item, i| if (std.mem.eql(u8, item, value)) return @intCast(i);
    return error.InvalidSession;
}
fn writeText(w: *std.Io.Writer, value: []const u8) !void {
    try w.writeInt(u16, @intCast(value.len), .little);
    try w.writeAll(value);
}
fn readText(r: *std.Io.Reader, target: anytype) !void {
    const value = try r.take(try r.takeInt(u16, .little));
    if (!target.set(value)) return error.InvalidSession;
}
fn readEnum(r: *std.Io.Reader, comptime T: type) !T {
    return std.enums.fromInt(T, try r.takeByte()) orelse error.InvalidSession;
}
fn encodeSession(s: *const State, bytes: []u8) !u32 {
    var w = std.Io.Writer.fixed(bytes);
    try w.writeAll("ZGW1");
    try w.writeByte(@intCast(s.len));
    try w.writeInt(u16, @intCast(s.selected), .little);
    try w.writeInt(u16, @intCast(s.next_id), .little);
    try w.writeByte(s.filter);
    try w.writeByte(@backingInt(s.sort));
    try w.writeByte(s.font_size);
    try writeText(&w, s.query.slice());
    for (s.tasks[0..s.len]) |*task| {
        try w.writeInt(u16, @intCast(task.id), .little);
        try writeText(&w, task.title.slice());
        try writeText(&w, task.notes.slice());
        try w.writeByte(@backingInt(task.status));
        try w.writeByte(@backingInt(task.priority));
        try w.writeByte(task.owner);
    }
    try w.writeByte(@intCast(s.activity_len));
    try w.writeInt(u16, @intCast(s.next_activity), .little);
    for (s.activity[0..s.activity_len]) |*item| {
        try w.writeInt(u16, @intCast(item.id), .little);
        try w.writeInt(u16, @intCast(item.task), .little);
        try w.writeByte(try stringIndex(&activity_labels, item.label));
        try w.writeByte(try stringIndex(&activity_times, item.time));
        try writeText(&w, item.detail.slice());
    }
    return @intCast(w.buffered().len);
}
fn decodeSession(bytes: []const u8) !State {
    var r = std.Io.Reader.fixed(bytes);
    if (!std.mem.eql(u8, try r.take(4), "ZGW1")) return error.InvalidSession;
    var next = State{};
    next.len = try r.takeByte();
    next.selected = try r.takeInt(u16, .little);
    next.next_id = try r.takeInt(u16, .little);
    next.filter = try r.takeByte();
    next.sort = try readEnum(&r, @TypeOf(next.sort));
    next.font_size = try r.takeByte();
    if (next.len > max_tasks or next.next_id < 1 or next.next_id > 10000 or next.filter > 3 or
        next.font_size < 80 or next.font_size > 140 or next.font_size % 10 != 0) return error.InvalidSession;
    try readText(&r, &next.query);
    for (next.tasks[0..next.len], 0..) |*task, i| {
        task.id = try r.takeInt(u16, .little);
        if (task.id == 0 or task.id >= next.next_id) return error.InvalidSession;
        for (next.tasks[0..i]) |previous| if (previous.id == task.id) return error.InvalidSession;
        var code: [16]u8 = undefined;
        task.code = Text(16).from(try std.fmt.bufPrint(&code, "FW-{d}", .{100 + task.id}));
        try readText(&r, &task.title);
        try readText(&r, &task.notes);
        task.status = try readEnum(&r, Status);
        task.priority = try readEnum(&r, Priority);
        task.owner = try r.takeByte();
        if (task.owner >= owners.len) return error.InvalidSession;
    }
    if (if (next.len == 0) next.selected != 0 else indexOf(&next, next.selected) == null) return error.InvalidSession;
    next.activity_len = try r.takeByte();
    next.next_activity = try r.takeInt(u16, .little);
    if (next.activity_len > max_activity or next.next_activity == 0 or next.next_activity > 10000) return error.InvalidSession;
    for (next.activity[0..next.activity_len], 0..) |*item, i| {
        item.id = try r.takeInt(u16, .little);
        item.task = try r.takeInt(u16, .little);
        const label = try r.takeByte();
        const time = try r.takeByte();
        if (item.id == 0 or item.id > 10000 or item.id == next.next_activity or
            item.task == 0 or item.task >= next.next_id or label >= activity_labels.len or time >= activity_times.len) return error.InvalidSession;
        for (next.activity[0..i]) |previous| if (previous.id == item.id) return error.InvalidSession;
        item.label = activity_labels[label];
        item.time = activity_times[time];
        try readText(&r, &item.detail);
    }
    if (r.bufferedLen() != 0) return error.InvalidSession;
    next.notice = "Workspace restored for this tab.";
    return next;
}
pub export fn getSessionBuffer() usize {
    return @intFromPtr(&session_buffer);
}
pub export fn getSessionCapacity() u32 {
    return session_buffer.len;
}
pub export fn saveSession() u32 {
    return encodeSession(&state, &session_buffer) catch 0;
}
// Call only before mount/init; invalid input leaves state untouched.
pub export fn restoreSession(length: u32) u32 {
    if (mounted or length > session_buffer.len) return 0;
    const next = decodeSession(session_buffer[0..length]) catch return 0;
    state = next;
    session_prepared = true;
    return 1;
}

fn inputForTest(kind: Input, value: []const u8) void {
    @memcpy(exchange[0..value.len], value);
    _ = setInput(@backingInt(kind), @intCast(value.len));
}
test "workspace edits and reorders emit leaf and move patches" {
    try std.testing.expect(init() > 0);
    inputForTest(.title, "Reusable controls <&>");
    try std.testing.expectEqualStrings("Reusable controls <&>", state.tasks[2].title.slice());
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "H\t") == null);
    _ = dispatch(@backingInt(Action.up), 0);
    try std.testing.expectEqual(@as(u32, 3), state.tasks[1].id);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "M\t") != null);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "H\t") == null);
    try std.testing.expect(resync() > 0);
}
test "workspace font preference is bounded retained on reset and recovered" {
    _ = init();
    inputForTest(.notes, "Keep my draft");
    _ = dispatch(@backingInt(Action.font_increase), 0);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "--font-scale:110") != null);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "H\t") == null);
    try std.testing.expectEqualStrings("Keep my draft", state.tasks[2].notes.slice());
    for (0..30) |_| _ = dispatch(@backingInt(Action.font_increase), 0);
    try std.testing.expectEqual(@as(u8, 140), state.font_size);
    try std.testing.expectEqual(@as(u32, 0), dispatch(@backingInt(Action.font_increase), 0));
    _ = dispatch(@backingInt(Action.reset), 0);
    try std.testing.expectEqual(@as(u8, 140), state.font_size);
    try std.testing.expect(resync() > 0);
    try std.testing.expect(std.mem.indexOf(u8, output[0..output_len], "--font-scale:140") != null);
    for (0..30) |_| _ = dispatch(@backingInt(Action.font_decrease), 0);
    try std.testing.expectEqual(@as(u8, 80), state.font_size);
    try std.testing.expectEqual(@as(u32, 0), dispatch(@backingInt(Action.font_decrease), 0));
    _ = init();
    try std.testing.expectEqual(@as(u8, 100), state.font_size);
}

test "workspace bounds creation removal and malformed input" {
    _ = init();
    @memset(exchange[0..193], 'x');
    _ = setInput(@backingInt(Input.title), 193);
    try std.testing.expectEqualStrings("Build the component library", state.tasks[2].title.slice());
    exchange[0] = 0xff;
    _ = setInput(@backingInt(Input.title), 1);
    _ = setInput(@backingInt(Input.title), exchange.len + 1);
    try std.testing.expectEqualStrings("Build the component library", state.tasks[2].title.slice());
    for (0..30) |_| _ = dispatch(@backingInt(Action.add), 0);
    try std.testing.expectEqual(@as(usize, max_tasks), state.len);
    try std.testing.expect(resync() > 0);
    for (0..max_tasks) |_| _ = dispatch(@backingInt(Action.remove), 0);
    try std.testing.expectEqual(@as(usize, 0), state.len);
    try std.testing.expect(resync() > 0);
    _ = dispatch(@backingInt(Action.reset), 0);
    try std.testing.expectEqual(@as(usize, 8), state.len);
}
test "workspace filters and escaped maximum values survive recovery" {
    _ = init();
    inputForTest(.search, "COMPONENT");
    try std.testing.expect(matches(&state, &state.tasks[2]));
    try std.testing.expect(!matches(&state, &state.tasks[0]));
    _ = dispatch(@backingInt(Action.clear), 0);
    @memset(exchange[0..1024], '"');
    _ = setInput(@backingInt(Input.notes), 1024);
    try std.testing.expectEqual(@as(usize, 1024), state.tasks[2].notes.len);
    try std.testing.expect(resync() > 0);
}

test "workspace maximum escaped task collection admits full recovery" {
    var candidate = seed();
    candidate.len = max_tasks;
    var title: [192]u8 = @splat('"');
    var notes: [1024]u8 = @splat('"');
    for (&candidate.tasks, 0..) |*task, i| {
        task.* = .{ .id = @intCast(i + 1), .code = Text(16).from("FW-124"), .title = Text(192).from(&title), .notes = Text(1024).from(&notes) };
    }
    try std.testing.expect(render(.{ .candidate = candidate, .mode = .full }) > 0);
    try std.testing.expectEqual(@as(usize, max_tasks), state.len);
    try std.testing.expect(resync() > 0);
}

test "workspace sessions round trip bounded owned state without focus or theme" {
    var original = seed();
    original.len = max_tasks;
    original.next_id = max_tasks + 1;
    original.selected = max_tasks;
    original.filter = 2;
    original.sort = .priority;
    original.font_size = 140;
    original.focus_revision = 88;
    original.dark = true;
    var title: [192]u8 = @splat('"');
    var notes: [1024]u8 = @splat('"');
    for (&original.tasks, 0..) |*task, i| task.* = .{
        .id = @intCast(i + 1),
        .title = Text(192).from(&title),
        .notes = Text(1024).from(&notes),
        .status = .active,
        .priority = .low,
        .owner = 2,
    };
    original.query = Text(192).from(&title);
    original.activity_len = max_activity;
    original.next_activity = max_activity + 1;
    for (&original.activity, 0..) |*item, i| item.* = .{
        .id = @intCast(i + 1),
        .task = 24,
        .label = "Updated task details",
        .detail = Text(192).from(&title),
    };
    const length = try encodeSession(&original, &session_buffer);
    try std.testing.expect(length <= session_buffer.len);
    const restored = try decodeSession(session_buffer[0..length]);
    @memset(&session_buffer, 0); // Decoded state must not borrow the exchange buffer.
    try std.testing.expectEqual(@as(usize, 24), restored.len);
    try std.testing.expectEqual(@as(u32, 25), restored.next_id);
    try std.testing.expectEqual(@as(u32, 24), restored.selected);
    try std.testing.expectEqualStrings(&notes, restored.tasks[23].notes.slice());
    try std.testing.expectEqualStrings("FW-124", restored.tasks[23].code.slice());
    try std.testing.expectEqualStrings(&title, restored.activity[4].detail.slice());
    try std.testing.expectEqualStrings("Updated task details", restored.activity[4].label);
    try std.testing.expectEqualStrings(&title, restored.query.slice());
    try std.testing.expectEqual(original.sort, restored.sort);
    try std.testing.expectEqual(original.filter, restored.filter);
    try std.testing.expectEqual(original.font_size, restored.font_size);
    try std.testing.expectEqual(@as(u32, 0), restored.focus_revision);
    try std.testing.expect(!restored.dark);
    try std.testing.expect(render(.{ .candidate = restored, .mode = .full }) > 0);
    try std.testing.expect(resync() > 0);
}

test "workspace rejects malformed sessions atomically before mounting" {
    _ = init();
    mounted = false;
    defer mounted = true;
    const length = saveSession();
    for ([_]u32{ 0, 3, 4, length - 1, length + 1, session_buffer.len + 1 }) |bad_length| {
        try std.testing.expectEqual(@as(u32, 0), restoreSession(bad_length));
        try std.testing.expectEqualStrings("Build the component library", state.tasks[2].title.slice());
    }
    for ([_]usize{ 0, 4, 9, 10, 11 }) |offset| {
        _ = saveSession();
        session_buffer[offset] = 255; // Version, count, filter, enum and text scale.
        try std.testing.expectEqual(@as(u32, 0), restoreSession(length));
    }
    var bad = seed();
    bad.tasks[1].id = bad.tasks[0].id;
    try std.testing.expectEqual(@as(u32, 0), restoreSession(try encodeSession(&bad, &session_buffer)));
    bad = seed();
    bad.selected = 99;
    try std.testing.expectEqual(@as(u32, 0), restoreSession(try encodeSession(&bad, &session_buffer)));
    bad = seed();
    bad.next_id = 3;
    try std.testing.expectEqual(@as(u32, 0), restoreSession(try encodeSession(&bad, &session_buffer)));
    bad = seed();
    bad.tasks[0].owner = 3;
    try std.testing.expectEqual(@as(u32, 0), restoreSession(try encodeSession(&bad, &session_buffer)));
    bad = seed();
    bad.tasks[0].title.bytes[0] = 255;
    try std.testing.expectEqual(@as(u32, 0), restoreSession(try encodeSession(&bad, &session_buffer)));
    bad = seed();
    bad.next_activity = bad.activity[0].id;
    try std.testing.expectEqual(@as(u32, 0), restoreSession(try encodeSession(&bad, &session_buffer)));
    try std.testing.expectEqualStrings("Build the component library", state.tasks[2].title.slice());
    var valid = seed();
    valid.tasks[2].title = Text(192).from("Saved task 🧭");
    try std.testing.expectEqual(@as(u32, 1), restoreSession(try encodeSession(&valid, &session_buffer)));
    @memset(&session_buffer, 0);
    try std.testing.expect(init() > 0);
    try std.testing.expectEqualStrings("Saved task 🧭", state.tasks[2].title.slice());
    try std.testing.expectEqual(@as(u32, 0), restoreSession(saveSession()));
}
