# Request 069: Declarative Optimistic UI & Rollback Buffers

Status: implemented; declarative `:optimistic` attribute directives with client-side rollback snapshot buffers.

## Reusable Problem

In high-responsiveness applications (e.g. toggles, status pills, likes, quantity increments, checkbox completions), waiting for an asynchronous roundtrip (server response, database write, or WASM dispatch) creates perceived latency:
1. **Interactive Sluggishness**: Instant visual confirmation is critical for smooth user feedback.
2. **Failure Handling**: If an action is rejected by server authorization or network failure, reverting the DOM state manually is prone to out-of-sync bugs.
3. **Declarative Synchronization**: Applications need a coordinated rollback mechanism where optimistic state can be applied instantly and automatically restored if the action is aborted or rejected.

## Required Contract

1. **Template Directive**:
   - Syntax: `:optimistic="action-name"` or `:optimistic="class:busy,attr:data-active"`.
   - Compiles into `data-optimistic="spec"` on interactive elements (`<button>`, `<input>`, `<a>`).
2. **Rollback Buffer Execution**:
   - When an optimistic action is triggered, the runtime captures a lightweight node snapshot (current classes, attributes, text values) keyed by an `actionId`.
   - Immediately reflects `data-optimistic-state="pending"` and applies speculative attributes.
   - If confirmed by an incoming patch stream, the rollback snapshot is discarded and `data-optimistic-state="confirmed"`.
   - If an error or abort event occurs, calling `host.rollbackOptimistic(actionId)` cleanly restores the recorded snapshot without re-rendering or losing surrounding focus.
3. **Zero Runtime Heap Allocation**:
   - Rollback snapshots use a bounded ring-buffer cache with fixed capacity.

## Acceptance Checklist

- [x] Specify neutral capability contract for declarative optimistic UI and rollback buffers.
- [x] Add `:optimistic` directive support to template compiler (`tools/template/compiler.zig`).
- [x] Implement optimistic state tracking and rollback engine in `web/dom.js`.
- [x] Verify speculative state application, confirmation, and error rollback across Chromium and Firefox.
