pub const syntax_types = @import("syntax-types");
pub const Language = syntax_types.Language;
pub const Span = syntax_types.Span;
pub const Tokenizer = @import("html/Tokenizer.zig");

test {
    _ = Tokenizer;
}
