const std = @import("std");
const cdp = @import("cdp.zig");
const J = cdp.journey;

test "observed response headers are case insensitive" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const r: J.Request = .{ .id = "1", .url = "http://fixture.invalid/", .method = "GET", .post_data = "", .headers = try J.parse(arena.allocator(), "{\"X-Request-Id\":\"receipt\",\"Content-Type\":\"application/json\"}") };
    try std.testing.expectEqualStrings("receipt", J.str(r.header("x-request-id")));
    try std.testing.expectEqualStrings("application/json", J.str(r.header("CONTENT-TYPE")));
    try std.testing.expect(r.header("missing") == .null);
}

test "CDP exact numeric reply identity" {
    try std.testing.expectEqual(@as(?u32, 10), try cdp.WsSession.responseId(std.testing.allocator, "{\"id\":10,\"result\":{\"id\":1}}"));
    try std.testing.expectEqual(@as(?u32, null), try cdp.WsSession.responseId(std.testing.allocator, "{\"method\":\"Network.responseReceived\",\"params\":{\"id\":1}}"));
    try std.testing.expectError(error.InvalidProtocolReply, cdp.WsSession.responseId(std.testing.allocator, "{\"id\":\"1\"}"));
}

test "owned CDP actual input upload download isolation and origin denial" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    const browser = try J.Browser.start(a, io);
    defer browser.stop();
    const p = try browser.page(&.{});
    defer p.close();
    _ = try p.eval("document.body.innerHTML='<label>Name<input id=entry></label><input type=file id=file><button id=act>Download</button><button disabled>Disabled</button>';window.trusted=[];document.addEventListener('input',e=>trusted.push(e.isTrusted));document.querySelector('#act').onclick=()=>{const a=document.createElement(\"a\");a.href=URL.createObjectURL(new Blob([\"exact,bytes\\r\\n\"]));a.download=\"fixture.csv\";a.click()};true");
    try p.label("Name").fill("native input");
    try std.testing.expect(J.boolean(try p.eval("document.querySelector('#entry').value==='native input'&&trusted.length===1&&trusted[0]")));
    const owned = try a.print("{s}/upload.csv", .{browser.profile});
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = owned, .data = "header\nvalue\n" });
    try p.css("#file").file(owned);
    try std.testing.expectEqualStrings("header\nvalue\n", J.str(try p.eval("document.querySelector('#file').files[0].text()")));
    const download = try p.download(p.role(.{ .role = "button", .name = "Download" }), try a.print("{s}/result.csv", .{browser.profile}));
    try std.testing.expectEqualStrings("fixture.csv", J.str(J.field(download, "filename")));
    try std.testing.expectEqualStrings("exact,bytes\r\n", J.str(J.field(download, "csv")));
    _ = try p.eval("document.body.insertAdjacentHTML('beforeend','<section hidden><button>Download</button></section>');true");
    try std.testing.expectEqual(@as(usize, 1), try p.role(.{ .role = "button", .name = "Download" }).count());
    _ = try p.eval("window.onbeforeunload=e=>{e.preventDefault();e.returnValue='';};true");
    try p.reload();
    _ = try p.eval("document.body.innerHTML='<button>Download</button><button disabled>Disabled</button>';true");
    p.timeout_ms = 100;
    try std.testing.expectError(error.ElementNotActionable, p.role(.{ .role = "button", .name = "Disabled" }).click());
    _ = try p.eval("document.body.insertAdjacentHTML('beforeend','<div style=\"position:fixed;inset:0;z-index:999\"></div>');true");
    try std.testing.expectError(error.ElementNotActionable, p.role(.{ .role = "button", .name = "Download" }).click());
    try std.testing.expect(J.boolean(try p.eval("fetch('https://outside.invalid/probe').then(()=>false,()=>true)")));
    _ = try browser.command("Storage.setCookies", .{ .browserContextId = p.context, .cookies = .{.{ .name = "owned", .value = "one", .domain = "fixture.invalid", .path = "/" }} });
    const peer = try browser.page(&.{});
    defer peer.close();
    const cookies = try browser.command("Storage.getCookies", .{ .browserContextId = peer.context });
    try std.testing.expectEqual(@as(usize, 0), J.field(cookies, "cookies").array.items.len);
}
