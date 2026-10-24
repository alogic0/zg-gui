# Native Chrome automation with `cdp`

The public `cdp` Zig module is supplied by the `zig-cdp` package dependency. It
launches headless Chrome and controls it through the Chrome DevTools Protocol.
Use it for browser checks, page inspection, screenshots, file uploads, downloads,
and observing HTTP responses. It is a library: write a Zig executable or test
that imports it, then run that program.

Start with `cdp.journey` for an owned browser and page actions. The lower-level
`CdpClient` and `WsSession` types can connect to an existing local CDP endpoint.
The [journey contract](../../docs/native-browser.md) describes protocol limits and
failure behavior in more detail.

## Requirements

- Use the exact compiler in [`.zigversion`](../../.zigversion), currently
  **Zig 0.17.0**. This compiler spells its optimization modes `debug` and `safe`.
- The launcher currently looks for Chrome or Chromium at these Linux paths, in
  order: `/usr/bin/google-chrome`, `/usr/bin/google-chrome-stable`,
  `/usr/bin/chromium`, `/usr/bin/chromium-browser`.
- Run under a user account where Chrome can start with its normal sandbox.
  The launcher needs a writable `/tmp` and loopback networking.

Browser automation uses Zig and the installed browser. No Node.js package,
browser driver, or JavaScript automation service is required.

## Run a complete example

Save this as `cdp-smoke.zig` in a scratch directory. It creates a page in memory,
fills a field, clicks a button, checks the result, writes a screenshot, and closes
the browser. No web server is needed.

```zig
const std = @import("std");
const cdp = @import("cdp");
const J = cdp.journey;

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const browser = try J.Browser.start(arena.allocator(), init.io);
    defer browser.stop();

    const page = try browser.page(&.{});
    defer page.close();

    _ = try page.eval(
        \\document.body.innerHTML = `
        \\  <label>Name <input id="name"></label>
        \\  <button id="save">Save</button>
        \\  <p id="result"></p>
        \\`;
        \\document.querySelector('#save').onclick = () => {
        \\  document.querySelector('#result').textContent =
        \\    'Saved: ' + document.querySelector('#name').value;
        \\};
        \\true
    );

    try page.label("Name").fill("Sample");
    try page.role(.{ .role = "button", .name = "Save" }).click();
    try page.wait("document.querySelector('#result').textContent === 'Saved: Sample'");

    const result = try page.css("#result").innerText();
    if (!std.mem.eql(u8, result, "Saved: Sample")) return error.UnexpectedResult;

    try page.screenshot("cdp-smoke.png");
    std.debug.print("{s}: {s}; wrote cdp-smoke.png\n", .{ browser.version, result });
}
```

Use the package integration below to run this example. The dependency's build
module supplies its transitive imports; source-file imports are unsupported.
The command writes `cdp-smoke.png` in the working directory.

## Add the public module to a project

This checkout uses a local `zig_cdp` dependency at `../zig-cdp`. Keep that sibling
checkout available when building zg-gui, or adjust its `build.zig.zon` dependency
path. Both packages use the same pinned Zig compiler.

zg-gui re-exports the dependency's public `cdp` module for existing consumers.
In an existing Zig package, add a dependency to `build.zig.zon`, adjusting the
relative path:

```zig
.dependencies = .{
    .zg_gui = .{ .path = "../zg-gui" },
},
```

Save the example above as `src/main.zig` and use this `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const gui = b.dependency("zg_gui", .{});
    const exe = b.addExecutable(.{
        .name = "browser-check",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = b.graph.host,
            .optimize = b.standardOptimizeOption(.{}),
            .imports = &.{.{ .name = "cdp", .module = gui.module("cdp") }},
        }),
    });
    const run = b.addRunArtifact(exe);
    b.step("run", "Run the browser check").dependOn(&run.step);
}
```

Run `zig build run` from your package directory. The CDP module runs on the build
host; it is separate from the framework's WebAssembly application module. The
exported `cdp` module is currently configured with debug optimization.

## Open your application

Start your application's server separately. Replace the in-memory fixture with
navigation, and give the page the HTTP origins it needs:

```zig
const page = try browser.page(&.{
    "http://127.0.0.1:4180",
    "http://127.0.0.1:8080",
});
defer page.close();

try page.goto("http://127.0.0.1:4180/");
try page.role(.{ .role = "button", .name = "Save" }).waitEnabled();
```

Origins include the scheme, host, and port, with no path or trailing slash.
`localhost` and `127.0.0.1` are different origins. Include API, asset, and redirect
origins used by the application. Intercepted requests outside the allowlist are
blocked. `about:blank`, `data:`, and `blob:` URLs are allowed; an empty list is
useful for fixtures. This interception is scoped to the page and is not a
process-wide network sandbox.

`goto()` waits for a new document to finish loading. Wait separately for your
application's ready state or controls. The default viewport is 1280 × 720.

## Page actions

These snippets assume an open `page` and an application with the named controls.

| Task | Example |
| --- | --- |
| Fill a labeled input | `try page.label("Name").fill("Sample");` |
| Click a named button | `try page.role(.{ .role = "button", .name = "Save" }).click();` |
| Scope a locator | `try page.css("#settings").role(.{ .role = "button", .name = "Save" }).click();` |
| Wait for visible text | `try page.text("Saved").waitVisible();` |
| Read text | `const text = try page.css("#status").innerText();` |
| Set a checkbox | `try page.label("Enabled").checked(true);` |
| Select an option by value | `try page.label("Theme").select("dark");` |
| Press Enter | `try page.label("Search").pressEnter();` |
| Select a local file | `try page.css("input[type=file]").file("/absolute/path/input.csv");` |
| Capture a PNG | `try page.screenshot("screen.png");` |
| Reload | `try page.reload();` |

Actions generally require exactly one matching element. Scope ambiguous locators;
use `first()` or `nth(index)` when selecting by position is intentional. Clicks
check visibility, enabled state, hit testing, and stable geometry before sending
browser mouse events. `fill()` uses browser text input. `select()` assigns the
value and dispatches DOM events. File inputs may be hidden but must be enabled.

`page.eval(expression)` awaits promises and returns a `std.json.Value`.
`page.evaluate(function, argument)` serializes a Zig argument into a JavaScript
function call. Use it when passing values instead of interpolating JavaScript:

```zig
const matches = try page.evaluate(
    "expected => document.querySelector('#name').value === expected",
    "Sample",
);
if (!J.boolean(matches)) return error.UnexpectedValue;
```

`J.field`, `J.str`, `J.boolean`, and `J.number` help inspect returned JSON. They
return fallback values for missing or incompatible types; check the JSON tag
yourself when distinguishing a missing value matters. Use `page.command()` or
`browser.command()` for additional CDP methods, passing Zig structs as parameters.

## Observe a response or download

Mark the request history before the action that triggers a request:

```zig
const mark = try page.mark();
try page.role(.{ .role = "button", .name = "Save" }).click();
const response = try page.response(.{
    .after = mark,
    .method = "POST",
    .path = "/api/items",
});
if (response.failed or response.status != 200) return error.SaveFailed;
const bytes = response.body orelse return error.ResponseBodyUnavailable;
_ = bytes; // Inspect according to your application's response format.
```

The path match excludes the query string. `responseAny()` accepts several
matches. `response.header(name)` reads a response header case-insensitively.
Captured requests and bodies can contain credentials; redact reports as needed.

For a download, pass the control that starts it and the destination filename:

```zig
const download = try page.download(
    page.role(.{ .role = "button", .name = "Export" }),
    "export.csv",
);
const suggested_name = J.str(J.field(download, "filename"));
const contents = J.str(J.field(download, "csv"));
_ = suggested_name;
_ = contents;
```

`download()` waits for completion and writes the downloaded bytes to the supplied
path. Its current result uses the key `csv` for the content. The read limit is
20 MiB. Create destination directories before downloading or taking screenshots;
output files are written relative to the process working directory unless the
path is absolute. Existing output files are overwritten.

## Ownership and cleanup

Use an arena for one journey. The `defer` order in the complete example closes
the page, stops the browser, then releases the arena. Returned journey values,
strings, request records, and locators borrow from that arena. Copy anything
needed after its destruction. Keep the origin list alive while the page is open.

Each `Browser.start()` creates a fresh temporary profile and discovers its own
debug port. Each `browser.page()` creates a separate browser context, including
separate cookies and storage. `Page.close()` disposes that context;
`Browser.stop()` closes its browser, joins its process, and removes the temporary
profile. Screenshot and download outputs outside that profile remain yours.
Use one task per connection and let deferred cleanup run on errors.

For DOM identity checks, `try locator.handle()` retains the actual DOM element
instead of rerunning a selector. This is useful for checking that a render kept
the same input node and its focus.

## Connect to an existing browser

Use `CdpClient` for a browser already exposing CDP on `127.0.0.1`. The following
fragment assumes `a` is an allocator, `io` is a `std.Io`, and the endpoint listens
on port 9222. It creates and later closes only its own tab:

```zig
const client = cdp.CdpClient.init(a, io, 9222);
const target = try client.newTarget("about:blank");
defer target.deinit(a);
defer client.closeTarget(target.id) catch {};

var session = try client.connectWs(target.web_socket_debugger_url);
defer session.close();

const reply = try session.evaluateJson("document.title");
defer reply.deinit();
// reply.value is the complete CDP reply, including its result/error envelope.
```

This does not own or stop the existing browser. The lower-level API also does
not install the journey's origin filtering or locator behavior.
`WsSession.call()` and `evaluate()` return allocated raw replies: free them with
the session's allocator. Free events returned by `takeEvent()` too. For
`listTargets()`, call `deinit(a)` on every target, then free the returned slice.
Check CDP error envelopes when using raw calls.

## Verify and troubleshoot

Run from the zg-gui repository root:

```sh
zig build test-tools --summary all
zig build test-browser --summary all
```

The tool integration checks cover shutdown/profile cleanup, actual input,
uploads, downloads, cookie isolation, and origin denial against the external
module. The browser suite exercises the framework's DOM and WASM host through
that module. Expected negative checks print actionability diagnostics for disabled
and covered controls before passing. CDP implementation tests are maintained in
the dependency.

| Symptom | Check |
| --- | --- |
| `NoBrowserFound` | Install Chrome/Chromium at one of the supported paths. |
| `BrowserLaunchTimeout` | Check that the browser starts under the same user, its sandbox works, and `/tmp` is writable. Launcher stderr is currently suppressed. |
| Navigation or assets fail | Check the server and every required origin, including ports and redirects. |
| `ElementNotActionable` | Inspect the locator, viewport, overlays, and disabled state. Clicks scroll the element into view before hit testing. |
| `BrowserConditionTimeout` or `ResponseTimeout` | Check the condition or request match. Set `page.timeout_ms` when the application needs a longer wait. |
| `BrowserEvaluationFailed` | Check the JavaScript expression and the reported exception. |
| `UnexpectedBrowserDialog` | Explicit navigation/reload accepts `beforeunload`; other dialogs are dismissed and fail the journey. |

The default page timeout is 30 seconds; individual socket reads also have a
30-second timeout. Role/name matching is a bounded helper, not a complete
accessibility-name implementation. A failed wire connection must be closed.
See the [journey contract](../../docs/native-browser.md) for message and request
bounds, and [the tests](cdp_journey_test.zig) for additional fixtures.
