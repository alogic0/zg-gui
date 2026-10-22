# Revision-owned projection focus modes

Status: verified.

## Reusable problem and public API

A revision-owned focus request must let a consumer focus a target without
scrolling clipped ancestors. The existing DOM protocol already supports
preserve-scroll, nearest and text-end focus, but `Projection.focus` always emits
nearest scrolling.

Add an optional `mode: patch.FocusMode = .nearest` field to the named input of
`Projection.focus`. Consumers own the target, mode, route/viewport policy and
revision. An unchanged revision must not repeat focus or move the viewport,
regardless of a changed target/mode argument. New revisions emit the existing
focus protocol. Initial static rendering still emits no focus command.

No DOM protocol, allocation, node admission or host behavior changes. The host
continues rejecting text-end requests for incompatible controls. Each request
uses the existing single snapshot entry; overflow retains current failure
behavior. Existing callers retain nearest scrolling by default.

## Acceptance

- [x] Native projection checks cover default, preserve-scroll, text-end, initial
  rendering and unchanged revisions.
- [x] Browser checks retain target/ancestor identity and preserve clipped
  ancestor scroll offsets for preserve-scroll focus.
- [x] Public integration documentation and relevant core/browser checks pass.

Application styling, navigation policy and performance budgets remain outside
this provider contract. No new persistent state or allocator is introduced;
record actual patch lengths and any relevant measurement limits below.


Verification: `zig build test -j4` and `zig build test-browser -j4` passed.
The native test records one snapshot entry per request and exact focus frames:
12 bytes for nearest, 4 for preserve-scroll and 8 for text-end with target 2.
The browser check verifies preserved horizontal offsets and the identity of the
focused heading, its clipped ancestor and an unrelated draft input. The new
argument delegates existing protocol behavior; no host implementation changed.
WASM size and peak-memory benchmarks were not rerun for this optional argument.
