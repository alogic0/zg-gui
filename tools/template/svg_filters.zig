//! Finite, static SVG filter vocabulary used during template admission.
const std = @import("std");

fn oneOf(value: []const u8, list: []const u8) bool {
    var words = std.mem.tokenizeScalar(u8, list, ' ');
    while (words.next()) |word| if (std.mem.eql(u8, value, word)) return true;
    return false;
}
const primitives = "feGaussianBlur feOffset feColorMatrix feBlend feComposite feMorphology feComponentTransfer";
const channels = "feFuncR feFuncG feFuncB feFuncA";
pub fn isElement(tag: []const u8) bool {
    return std.mem.eql(u8, tag, "filter") or oneOf(tag, primitives) or oneOf(tag, channels);
}
pub fn structureError(input: struct { parent: []const u8, child: []const u8 }) ?[]const u8 {
    if (std.mem.eql(u8, input.child, "filter") and !std.mem.eql(u8, input.parent, "defs")) return "SVG filters require defs";
    if (oneOf(input.child, primitives) and !std.mem.eql(u8, input.parent, "filter")) return "SVG primitives require a filter parent";
    if (oneOf(input.child, channels) and !std.mem.eql(u8, input.parent, "feComponentTransfer")) return "SVG channel functions require feComponentTransfer";
    if (std.mem.eql(u8, input.parent, "filter") and !oneOf(input.child, primitives)) return "filters accept only supported primitives";
    if (std.mem.eql(u8, input.parent, "feComponentTransfer") and !oneOf(input.child, channels)) return "component transfer accepts only channel functions";
    if ((oneOf(input.parent, primitives) and !std.mem.eql(u8, input.parent, "feComponentTransfer")) or oneOf(input.parent, channels)) return "SVG filter primitive cannot contain elements";
    return null;
}
pub fn attributeAllowed(tag: []const u8, name: []const u8) bool {
    if (oneOf(name, "id class role") or std.mem.startsWith(u8, name, "data-") or std.mem.startsWith(u8, name, "aria-")) return true;
    if (std.mem.eql(u8, tag, "filter")) return oneOf(name, "x y width height filterUnits primitiveUnits color-interpolation-filters");
    if (oneOf(tag, channels)) return oneOf(name, "type tableValues slope intercept amplitude exponent offset");
    if (oneOf(name, "in result x y width height color-interpolation-filters")) return true;
    if (std.mem.eql(u8, tag, "feGaussianBlur")) return oneOf(name, "stdDeviation edgeMode");
    if (std.mem.eql(u8, tag, "feOffset")) return oneOf(name, "dx dy");
    if (std.mem.eql(u8, tag, "feColorMatrix")) return oneOf(name, "type values");
    if (std.mem.eql(u8, tag, "feBlend")) return oneOf(name, "in2 mode");
    if (std.mem.eql(u8, tag, "feComposite")) return oneOf(name, "in2 operator k1 k2 k3 k4");
    if (std.mem.eql(u8, tag, "feMorphology")) return oneOf(name, "operator radius");
    return false;
}
fn identifier(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) return false;
    return true;
}
pub fn localReference(value: []const u8) bool {
    if (std.mem.eql(u8, value, "none")) return true;
    return std.mem.startsWith(u8, value, "url(#") and std.mem.endsWith(u8, value, ")") and value.len > 6 and identifier(value[5 .. value.len - 1]);
}
fn number(value: []const u8, nonnegative: bool) bool {
    if (value.len == 0) return false;
    for (value) |byte| if (std.mem.indexOfScalar(u8, "0123456789+-.eE", byte) == null) return false;
    const n = std.fmt.parseFloat(f64, value) catch return false;
    return std.math.isFinite(n) and (!nonnegative or n >= 0);
}
fn numbers(value: []const u8, nonnegative: bool, max: usize) bool {
    var tokens = std.mem.tokenizeAny(u8, value, " ,\t\r\n");
    var count: usize = 0;
    while (tokens.next()) |token| {
        count += 1;
        if (count > max or !number(token, nonnegative)) return false;
    }
    return count > 0;
}
pub fn validValue(input: struct { tag: []const u8, name: []const u8, value: []const u8 }) bool {
    const n = input.name;
    const v = input.value;
    if (oneOf(n, "id in in2 result")) return identifier(v);
    if (oneOf(n, "filterUnits primitiveUnits")) return oneOf(v, "userSpaceOnUse objectBoundingBox");
    if (std.mem.eql(u8, n, "color-interpolation-filters")) return oneOf(v, "sRGB linearRGB");
    if (std.mem.eql(u8, n, "mode")) return oneOf(v, "normal multiply screen darken lighten");
    if (std.mem.eql(u8, n, "edgeMode")) return oneOf(v, "duplicate wrap none");
    if (std.mem.eql(u8, n, "operator")) return if (std.mem.eql(u8, input.tag, "feMorphology")) oneOf(v, "erode dilate") else oneOf(v, "over in out atop xor arithmetic");
    if (std.mem.eql(u8, n, "type")) return if (std.mem.eql(u8, input.tag, "feColorMatrix")) oneOf(v, "matrix saturate hueRotate luminanceToAlpha") else oneOf(v, "identity table discrete linear gamma");
    if (oneOf(n, "x y width height")) return number(if (std.mem.endsWith(u8, v, "%")) v[0 .. v.len - 1] else v, oneOf(n, "width height"));
    // First blur API deliberately admits one scalar, not an anisotropic pair.
    if (std.mem.eql(u8, n, "stdDeviation")) return number(v, true);
    if (std.mem.eql(u8, n, "radius")) return numbers(v, true, 2);
    if (std.mem.eql(u8, n, "values")) return numbers(v, false, 20);
    if (std.mem.eql(u8, n, "tableValues")) return numbers(v, false, 256);
    if (oneOf(n, "dx dy k1 k2 k3 k4 slope intercept amplitude exponent offset")) return number(v, false);
    return true;
}
