# HTML writer streaming adaptors, form element helpers, and zero-allocation data formatters

Status: implemented and provider verified; consumer acceptance is separate.

Server-side HTML rendering and dashboard tooling require streaming formatted
data, standard form controls, semantic timestamps, and humanized data metrics
without intermediate heap allocations or redundant boilerplate across consumers.

`zg_gui.html.Writer` provides the following additions:

- `openStream(self: *Writer) Stream`: returns a streaming adapter wrapping
  `std.Io.Writer.fixed` pointing directly into the remaining buffer capacity.
  Calling `stream.finish()` advances `Writer.len` by the number of bytes written.
- `writeStream(self: *Writer, comptime action: anytype, args: anytype) void`:
  invokes a formatting callback receiving `*std.Io.Writer` with arguments,
  automatically advancing buffer length and marking `Writer.failed = true` on
  overflow or failure.
- `option(self: *Writer, value: []const u8, label: []const u8, selected: bool) void`:
  emits `<option value="..." selected>label</option>` with proper HTML attribute
  and body escaping and boolean selection attribute.
- `time(self: *Writer, datetime: []const u8, label: []const u8) void`:
  emits `<time datetime="...">label</time>` with attribute and body escaping.
- `tag(self: *Writer, element: []const u8, content: []const u8) void`:
  emits `<element>content</element>` with content escaping.
- `formatBytes(self: *Writer, bytes: u64) void`:
  formats binary byte counts with exact 1-decimal precision and unit suffixes
  (`B`, `KB`, `MB`, `GB`, `TB`, `PB`) without floating-point inaccuracies or heap
  allocations.
- `formatDuration(self: *Writer, ms: u64) void`:
  formats millisecond durations into humanized strings (`45ms`, `1.5s`, `2m 15s`,
  `1h 30m`) without allocations.

All methods respect the caller-provided buffer bounds, never reallocate, and set
`self.failed = true` on buffer exhaustion.

Verification: unit tests in `src/html.zig` exercise streams, custom formatters,
option rendering with/without selection, time tags, byte units, durations, and
buffer overflow behavior.
