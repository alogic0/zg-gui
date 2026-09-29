const std = @import("std");
const compiler = @import("compiler.zig");
const formatter = @import("formatter.zig");

fn printHelp(io: std.Io) void {
    const msg =
        \\Usage:
        \\  zg-template <template.gui.html> <output.zig> [--context=ctx] [name path...]
        \\  zg-template fmt [options] <files...>
        \\  zg-template format [options] <files...>
        \\  zg-fmt [options] <files...>
        \\
        \\Commands:
        \\  fmt, format       Format/beautify template files
        \\
        \\Options:
        \\  -h, --help        Show this help message
        \\
    ;
    var stdout = std.Io.File.stdout();
    _ = stdout.writeStreamingAll(io, msg) catch {};
}

fn printFmtHelp(io: std.Io) void {
    const msg =
        \\Usage:
        \\  zg-fmt [options] <files...>
        \\  zg-template fmt [options] <files...>
        \\
        \\Options:
        \\  -w, --write       Write result to source file(s) in-place
        \\  -c, --check       Check if files are formatted; exits with 1 if unformatted
        \\  --indent=N        Number of spaces per indentation level (default: 2)
        \\  --max-width=N     Maximum line width threshold for inlining tags (default: 100)
        \\  -h, --help        Show this help message
        \\
        \\If file is '-' or no files are provided, reads standard input and writes to standard output.
        \\
    ;
    var stdout = std.Io.File.stdout();
    _ = stdout.writeStreamingAll(io, msg) catch {};
}

fn runFormatter(init: std.process.Init, first_arg: ?[:0]const u8, args: *std.process.Args.Iterator) !void {
    const allocator = init.arena.allocator();
    var write_mode = false;
    var check_mode = false;
    var indent_size: u32 = 2;
    var max_width: u32 = 120;
    var files = std.ArrayList([]const u8).empty;

    var current_arg: ?[:0]const u8 = first_arg;
    while (current_arg) |arg| {
        defer current_arg = args.next();
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printFmtHelp(init.io);
            return;
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--write")) {
            write_mode = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--check")) {
            check_mode = true;
        } else if (std.mem.startsWith(u8, arg, "--indent=")) {
            indent_size = std.fmt.parseInt(u32, arg[9..], 10) catch {
                std.debug.print("error: invalid indent size '{s}'\n", .{arg[9..]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "--max-width=")) {
            max_width = std.fmt.parseInt(u32, arg[12..], 10) catch {
                std.debug.print("error: invalid max width '{s}'\n", .{arg[12..]});
                std.process.exit(1);
            };
        } else if (std.mem.startsWith(u8, arg, "-")) {
            if (std.mem.eql(u8, arg, "-")) {
                try files.append(allocator, "-");
            } else {
                std.debug.print("error: unknown option '{s}'\n", .{arg});
                std.process.exit(1);
            }
        } else {
            try files.append(allocator, arg);
        }
    }

    if (files.items.len == 0) {
        try files.append(allocator, "-");
    }

    if (!write_mode and !check_mode and files.items.len > 1) {
        std.debug.print("error: multiple files specified without -w (--write) or -c (--check)\n", .{});
        std.process.exit(1);
    }

    var any_unformatted = false;
    for (files.items) |file_path| {
        const is_stdin = std.mem.eql(u8, file_path, "-");
        const source = if (is_stdin) blk: {
            var stdin_file = std.Io.File.stdin();
            var buf: [4096]u8 = undefined;
            var reader = stdin_file.readerStreaming(init.io, &buf);
            break :blk reader.interface.allocRemaining(allocator, .limited(compiler.max_source_bytes)) catch |err| {
                std.debug.print("error: failed to read stdin: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
        } else blk: {
            break :blk std.Io.Dir.cwd().readFileAlloc(init.io, file_path, allocator, .limited(compiler.max_source_bytes)) catch |err| {
                std.debug.print("error: failed to read file '{s}': {s}\n", .{ file_path, @errorName(err) });
                std.process.exit(1);
            };
        };

        var diagnostic = formatter.Diagnostic{};
        const formatted = formatter.format(allocator, source, .{
            .indent_size = indent_size,
            .max_line_width = max_width,
            .diagnostic = &diagnostic,
            .file_name = if (is_stdin) "<stdin>" else file_path,
        }) catch |err| {
            if (err == error.InvalidTemplate) {
                std.debug.print("{s}:{d}:{d}: {s}\n", .{ diagnostic.name, diagnostic.line, diagnostic.column, diagnostic.message });
                std.process.exit(1);
            }
            return err;
        };

        if (check_mode) {
            if (!std.mem.eql(u8, source, formatted)) {
                std.debug.print("{s} is not formatted\n", .{if (is_stdin) "<stdin>" else file_path});
                any_unformatted = true;
            }
        } else if (write_mode) {
            if (is_stdin) {
                std.debug.print("error: cannot use -w with standard input\n", .{});
                std.process.exit(1);
            }
            if (!std.mem.eql(u8, source, formatted)) {
                try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = file_path, .data = formatted });
            }
        } else {
            var stdout = std.Io.File.stdout();
            try stdout.writeStreamingAll(init.io, formatted);
        }
    }

    if (check_mode and any_unformatted) {
        std.process.exit(1);
    }
}

pub fn main(init: std.process.Init) !void {
    var args = std.process.Args.Iterator.init(init.minimal.args);
    const exe_name = args.next() orelse return error.MissingExecutableName;

    const is_zg_fmt = std.mem.endsWith(u8, exe_name, "zg-fmt") or std.mem.eql(u8, exe_name, "zg-fmt");
    if (is_zg_fmt) {
        try runFormatter(init, args.next(), &args);
        return;
    }

    const first_arg = args.next() orelse {
        printHelp(init.io);
        return;
    };

    if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help")) {
        printHelp(init.io);
        return;
    }

    if (std.mem.eql(u8, first_arg, "fmt") or std.mem.eql(u8, first_arg, "format")) {
        try runFormatter(init, args.next(), &args);
        return;
    }

    const source_path = first_arg;
    const output_path = args.next() orelse return error.MissingOutputPath;
    const allocator = init.arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(init.io, source_path, allocator, .limited(compiler.max_source_bytes));
    var components: std.ArrayList(compiler.Component) = .empty;
    var fragment_context: compiler.FragmentContext = .flow;
    var pending = args.next();
    if (pending) |arg| {
        if (std.mem.startsWith(u8, arg, "--context=")) {
            fragment_context = std.meta.stringToEnum(compiler.FragmentContext, arg[10..]) orelse return error.InvalidFragmentContext;
            pending = args.next();
        }
    }
    while (pending) |name| {
        pending = null;
        const path = args.next() orelse return error.MissingComponentPath;
        if (components.items.len == 64) return error.TooManyComponents;
        const contents = try std.Io.Dir.cwd().readFileAlloc(init.io, path, allocator, .limited(compiler.max_source_bytes));
        try components.append(allocator, .{ .name = name, .file = .{ .name = path, .source = contents } });
        pending = args.next();
    }
    var diagnostic = compiler.Diagnostic{};
    const code = compiler.compile(allocator, .{ .source = source, .name = source_path, .diagnostic = &diagnostic, .components = components.items, .fragment_context = fragment_context }) catch |err| {
        if (err == error.InvalidTemplate) {
            std.debug.print("{s}:{d}:{d}: {s}\n", .{ diagnostic.name, diagnostic.line, diagnostic.column, diagnostic.message });
            std.process.exit(1);
        }
        return err;
    };
    // No output is opened until parsing, validation and generation succeed.
    try std.Io.Dir.cwd().writeFile(init.io, .{ .sub_path = output_path, .data = code });
}
