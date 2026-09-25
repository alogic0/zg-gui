# Request 065: Cross-Frame Binary Patch Synchronization

Status: implemented; zero-copy binary patch transfers across `postMessage` / `MessagePort` boundaries with `ArrayBuffer` transfer lists and origin validation.

## Reusable Problem

Complex enterprise applications often run untrusted plugins, sandboxed preview frames, or isolated microfrontends inside `<iframe>` elements or child browsing contexts:
1. **Serialization Bottleneck**: Passing large UI DOM patch buffers across frame boundaries via stringified JSON incurs heavy serialization, GC pressure, and frame drops.
2. **Security & Origin Leaks**: Blindly listening to `window.addEventListener('message', ...)` without origin checking or channel binding invites cross-site message injection.
3. **Buffer Cloning Overhead**: Cloning large binary snapshots across threads duplicates linear memory when transfer ownership (`transfer: [buffer]`) could achieve zero-copy handoff.

## Required Contract

1. **Structured Message Protocol**:
   - Standard patch packet format:
     ```js
     {
       type: 'zg:patch-stream',
       buffer: ArrayBuffer, // transferred zero-copy
     }
     ```
2. **Cross-Frame Channel Receiver**:
   - `createFrameSyncHost({ root, origin, port })`:
     - Binds a dedicated `MessagePort` or listens to validated `window.postMessage` events matching `expectedOrigin`.
     - Automatically passes the received `ArrayBuffer` to `applyPatchStream(buffer)`.
     - Validates protocol headers and rejects malformed or unverified origin events.
3. **Zero-Copy Transfer**:
   - Transmitters pass binary patch buffers via `target.postMessage(message, targetOrigin, [buffer])` or `port.postMessage(message, [buffer])`.
4. **Disposal**:
   - Disconnecting the channel removes message listeners and disposes the associated DOM host.

## Acceptance Checklist

- [x] Specify cross-frame binary patch sync contract.
- [x] Implement `createFrameSyncHost` and transfer protocol in `web/dom.js`.
- [x] Enforce origin validation and structured message bounds.
- [x] Multi-engine browser verification across Chromium and Firefox.
