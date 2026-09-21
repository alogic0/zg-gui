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
    focus_revision: u32 = 0,
    activity: [max_activity]Activity = @splat(.{}),
    activity_len: usize = 0,
    next_activity: u32 = 1,
    notice: []const u8 = "Sample workspace. Changes stay in this session.",
};
const Action = enum(u32) { select = 1, complete, filter, add, remove, up, down, theme, reset, clear };
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
        .dark = s.dark,
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
        .metric_progress = Metric{ .label = "Overall progress", .value = std.fmt.bufPrint(&progress_value, "{d}%", .{percent}) catch unreachable, .note = std.fmt.bufPrint(&progress_note, "{d} of {d} tasks complete", .{ counts[2], s.len }) catch unreachable, .icon = "workspace-icons.svg#progress", .progress = progress, .show_progress = true },
        .metric_active = Metric{
            .label = "In progress",
            .value = std.fmt.bufPrint(&active_value, "{d}", .{counts[1]}) catch unreachable,
            .note = "Good things are taking shape",
            .icon = "workspace-icons.svg#layers",
            .progress = progress,
            .show_chart = true,
            .chart_label = std.fmt.bufPrint(&chart_label, "{d} to do, {d} in progress, {d} done", .{ counts[0], counts[1], counts[2] }) catch unreachable,
            .chart = .{ .planned_y = 24 - planned_height, .planned_height = planned_height, .active_y = 24 - active_height, .active_height = active_height, .done_y = 24 - done_height, .done_height = done_height },
        },
        .metric_planned = Metric{ .label = "Up next", .value = std.fmt.bufPrint(&planned_value, "{d}", .{counts[0]}) catch unreachable, .note = "Ready when you are", .icon = "workspace-icons.svg#arrow", .progress = progress },
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
        .actions = .{ .select = Action.select, .complete = Action.complete, .filter = Action.filter, .add = Action.add, .remove = Action.remove, .up = Action.up, .down = Action.down, .theme = Action.theme, .reset = Action.reset, .clear = Action.clear },
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
    return render(.{ .candidate = seed(), .mode = .full });
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
        .theme => next.dark = !next.dark,
        .reset => {
            const dark = next.dark;
            next = seed();
            next.dark = dark;
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
            next.notice = "Changes saved for this session.";
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
