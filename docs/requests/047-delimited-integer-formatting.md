# Formatted integer and delimited number serialization

Status: implemented and provider verified; consumer acceptance is separate.

Server-rendered views, table metrics, and financial summaries frequently require
grouping separators (such as thousands commas) and direct integer serialization
into bounded HTML output. Zig's standard format specifiers do not provide
grouping delimiters, requiring consumers to allocate intermediate strings or
implement ad-hoc stack formatting routines.

`zg_gui.html.Writer` now provides zero-allocation integer formatting methods that
write directly into the caller-owned buffer:

- `int(value: anytype) void`: serializes signed or unsigned integers directly
  into the output slice.
- `intDelimited(value: anytype, delimiter: u8) void`: serializes signed or
  unsigned integers with a custom grouping delimiter (e.g., `,`, `_`, or space)
  grouped every three digits from the right.
- `intCommas(value: anytype) void`: convenience wrapper using comma delimiters
  (`1,234,567`).
- `attribute(name: []const u8, value: []const u8) void`: emits an attribute name
  and safely escaped value (` name="escaped_value"`).
- `booleanAttribute(name: []const u8, present: bool) void`: emits the attribute
  name when present is true (` name`).

Buffer overflow sets `writer.failed = true` and halts further emission without
corrupting or reallocating memory, adhering to the framework's strict bounded
buffer contract. Two's complement edge cases (`std.math.minInt`) and unsigned
64-bit maximums are supported safely without integer overflow.

Verification: unit tests in `src/html.zig` exercise zero, small values, negative
integers, powers of ten, grouping boundaries, `minInt(i64)`, `maxInt(u64)`,
custom delimiters, and exact buffer overflow rejection. All 45 repository unit
and host tests and all 37 browser journey checks pass.
