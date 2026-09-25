# Request 057: Web Worker offscreen projections

Status: implemented and verified.

## Reusable problem

In data-intensive applications—such as live trading dashboards, real-time audio/telecom monitors,
large-scale log viewers, and high-frequency analytical tables—state mutation and view projection
can occur dozens of times per second.

When the Zig WebAssembly module runs on the main browser thread alongside the DOM host, heavy
projection diffing and large-scale snapshot evaluations compete directly with UI rendering,
scrolling, gesture handling, and CSS animations. This can lead to main-thread starvation and
noticeable frame drops (jank).

Offloading the WebAssembly instance to a background Web Worker isolates compute from rendering.
However, conventional Web Worker setups introduce serialization bottlenecks (e.g. JSON stringify/parse
or structured cloning of complex state trees) that often exceed the compute cost itself.

This request delivers Web Worker offscreen projections by running the Zig WASM instance in a
background Worker and transferring binary patch buffers zero-copy (`ArrayBuffer` transfer) to the
main-thread DOM host.

## Required contract

1. **Architecture & Thread Separation**:
   - **Worker Thread**:
     - Owns the WebAssembly instance, memory allocations, application state, and view models.
     - Performs snapshot diffing and writes compact binary patch commands into a pre-allocated
       transfer buffer.
     - Dispatches patch updates via `postMessage({ type: 'patch', buffer }, [buffer])`.
   - **Main Thread**:
     - Maintains a lightweight DOM host (`dom.js` / `worker-host.js`).
     - Directly applies received binary patch buffers to the live DOM tree.
     - Forwards user DOM events (clicks, inputs, focus changes) to the Worker as compact event
       tuples (`{ type: 'input', id: nodeId, value: str }`).

2. **Zero-Copy Binary Patch Transfer**:
   - The wire patch protocol uses binary encodings or compact token streams.
   - The backing `ArrayBuffer` of the patch writer is transferred (not copied) via `postMessage`,
     relinquishing ownership in the Worker and avoiding all serialization or memory cloning overhead.
   - The Worker uses a double-buffering or pool strategy to alternate patch buffers without
     reallocating heap memory.

3. **Bidirectional Event Transport**:
   - DOM input and action events captured on the main thread are serialized into a minimal binary or
     compact array format before dispatching to the Worker.
   - Controlled input fields maintain local optimistic feedback on the main thread to ensure
     zero-latency typing while the Worker processes validation asynchronously.

4. **Lifecycle & Fallback**:
   - Provide a unified consumer API (`createApp({ worker: true })` vs `createApp({ worker: false })`).
   - If Web Workers are unavailable (e.g. restrictive CSP or specific test runners), the framework
     gracefully falls back to running the WASM module directly on the main thread with identical
     rendering semantics.

## Acceptance checklist

- [x] Specify Worker message protocol and binary patch buffer transfer format.
- [x] Implement Worker-based projection runner and main-thread `WorkerDomHost`.
- [x] Implement zero-copy buffer transfer with double-buffering/recycling to prevent allocations.
- [x] Implement input event forwarding with optimistic text/control handling.
- [x] Measure throughput and frame rates under high-frequency updates (e.g. 60 FPS state sweeps).
- [x] Verify memory stability and absence of memory leaks or buffer fragmentation across 10,000+
      consecutive transfers.
- [x] Verify identical DOM rendering output between main-thread and worker-thread execution.
- [x] Verify multi-engine browser compatibility (Chromium, Firefox Gecko, WebKit).
