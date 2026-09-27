//! Native browser worker and offscreen projection test suite for zg-gui.
//! Ports all 6 tests from tests/worker.test.mjs.
const std = @import("std");
const harness = @import("../browser_harness.zig");
const Harness = harness.Harness;

test "browser worker: zero-copy double-buffering recycling preserves bounded pool size across 10,000+ transfers" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");
    try guard.evalCheck(
        \\const resp = await fetch('/demo.wasm');
        \\const wasmBytes = await resp.arrayBuffer();
        \\const wasmModule = await WebAssembly.compile(wasmBytes);
        \\const { createProjectionRunner } = await import('/projection-worker.js');
        \\
        \\let renderCount = 0;
        \\let lastBuffer = null;
        \\const uniqueBuffers = new Set();
        \\
        \\const runner = createProjectionRunner({
        \\  postMessage: (msg, transfer) => {
        \\    if (msg.type === 'render') {
        \\      renderCount++;
        \\      assert.ok(msg.buffer instanceof ArrayBuffer);
        \\      assert.ok(transfer && transfer.includes(msg.buffer));
        \\      lastBuffer = msg.buffer;
        \\      uniqueBuffers.add(msg.buffer);
        \\    }
        \\  }
        \\});
        \\
        \\await runner.handleMessage({ type: 'init', wasmModule });
        \\assert.equal(renderCount, 1);
        \\assert.ok(lastBuffer);
        \\
        \\// Return initial buffer
        \\await runner.handleMessage({ type: 'recycle', buffer: lastBuffer });
        \\
        \\// Run 10,000 state transitions alternating actions
        \\for (let i = 0; i < 10000; i++) {
        \\  // Action 1 is increment, Action 4 is decrement
        \\  await runner.handleMessage({ type: 'dispatch', action: (i % 2 === 0 ? 1 : 4), value: 0 });
        \\  assert.ok(lastBuffer);
        \\  // Recycle buffer back zero-copy
        \\  await runner.handleMessage({ type: 'recycle', buffer: lastBuffer });
        \\}
        \\
        \\assert.equal(renderCount, 10001);
        \\assert.ok(runner.getPoolSize() <= 2, `Pool size should be <= 2, got ${runner.getPoolSize()}`);
        \\assert.ok(uniqueBuffers.size <= 4, `Unique buffers created should be <= 4, got ${uniqueBuffers.size}`);
        \\runner.dispose();
        \\return true;
    );
}

test "browser worker: identical DOM projection between worker-based host and main-thread runtime" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");
    try guard.evalCheck(
        \\const { createApp, load } = await import('/runtime.js');
        \\
        \\const workerRoot = document.createElement('div');
        \\const mainRoot = document.createElement('div');
        \\document.body.append(workerRoot, mainRoot);
        \\
        \\const workerApp = await createApp({ root: workerRoot, wasmUrl: '/demo.wasm', worker: true });
        \\const mainApp = await load({ root: mainRoot, url: '/demo.wasm' });
        \\
        \\// Compare initial projections
        \\if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        \\  throw new Error('Initial projections do not match');
        \\}
        \\
        \\// Execute a sequence of mutations on both
        \\// 1: Increment counter
        \\workerApp.dispatch({ action: 1 });
        \\mainApp.dispatch({ action: 1 });
        \\await new Promise(r => setTimeout(r, 50));
        \\if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        \\  throw new Error('Projections mismatch after increment');
        \\}
        \\
        \\// 2: Open details (action 2)
        \\workerApp.dispatch({ action: 2 });
        \\mainApp.dispatch({ action: 2 });
        \\await new Promise(r => setTimeout(r, 50));
        \\if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        \\  throw new Error('Projections mismatch after details toggle');
        \\}
        \\
        \\// 3: Input name
        \\workerApp.setInput({ kind: 1, value: 'Worker Projection' });
        \\mainApp.setInput({ kind: 1, value: 'Worker Projection' });
        \\await new Promise(r => setTimeout(r, 50));
        \\if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        \\  throw new Error('Projections mismatch after setInput');
        \\}
        \\
        \\// 4: Toggle theme (action 7)
        \\workerApp.dispatch({ action: 7 });
        \\mainApp.dispatch({ action: 7 });
        \\await new Promise(r => setTimeout(r, 50));
        \\if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        \\  throw new Error('Projections mismatch after theme toggle');
        \\}
        \\
        \\workerApp.dispose();
        \\mainApp.dispose();
        \\workerRoot.remove();
        \\mainRoot.remove();
        \\return true;
    );
}

test "browser worker: Web Worker offscreen projection preserves user typing and optimistic draft" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");
    try guard.evalCheck(
        \\const { createApp } = await import('/runtime.js');
        \\const root = document.createElement('main');
        \\document.body.append(root);
        \\
        \\const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true });
        \\const nameInput = root.querySelector('#name');
        \\if (!nameInput) throw new Error('#name input not found');
        \\
        \\nameInput.focus();
        \\nameInput.value = 'Optimistic Worker Value';
        \\nameInput.dispatchEvent(new Event('input', { bubbles: true }));
        \\
        \\// Give worker time to respond with patch
        \\await new Promise(r => setTimeout(r, 80));
        \\
        \\const inputRetained = (document.activeElement === nameInput)
        \\  && (nameInput.value === 'Optimistic Worker Value')
        \\  && (root.querySelector('#greeting')?.textContent === 'Optimistic Worker Value');
        \\
        \\app.dispose();
        \\root.remove();
        \\assert.ok(inputRetained);
        \\return true;
    );
}

test "browser worker: high-frequency state sweep (60 FPS burst) under worker execution" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");
    try guard.evalCheck(
        \\const { createApp } = await import('/runtime.js');
        \\const root = document.createElement('main');
        \\document.body.append(root);
        \\
        \\const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true });
        \\
        \\// Dispatch 60 actions rapidly
        \\for (let i = 0; i < 60; i++) {
        \\  app.dispatch({ action: 1 });
        \\}
        \\
        \\// Wait for worker queue to settle
        \\await new Promise(r => setTimeout(r, 200));
        \\
        \\const countText = root.querySelector('.counter output')?.textContent;
        \\app.dispose();
        \\root.remove();
        \\assert.equal(countText, '60');
        \\return true;
    );
}

test "browser worker: createApp falls back to main-thread execution when Worker is unavailable" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");
    try guard.evalCheck(
        \\const originalWorker = window.Worker;
        \\try {
        \\  window.Worker = undefined;
        \\  const { createApp } = await import('/runtime.js');
        \\  const root = document.createElement('main');
        \\  document.body.append(root);
        \\
        \\  const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true });
        \\  const initialCount = root.querySelector('.counter output')?.textContent;
        \\
        \\  app.dispatch({ action: 1 });
        \\  const incrementedCount = root.querySelector('.counter output')?.textContent;
        \\
        \\  app.dispose();
        \\  root.remove();
        \\  assert.equal(initialCount, '0');
        \\  assert.equal(incrementedCount, '1');
        \\  return true;
        \\} finally {
        \\  window.Worker = originalWorker;
        \\}
    );
}

test "browser worker: createApp with worker: true and hydrate: true seamlessly hydrates pre-rendered markup" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");
    try guard.evalCheck(
        \\const { createApp, load } = await import('/runtime.js');
        \\
        \\// Create a temporary main app to obtain the exact pre-rendered HTML projection
        \\const tempRoot = document.createElement('div');
        \\const tempApp = await load({ root: tempRoot, url: '/demo.wasm' });
        \\const serverHtml = tempRoot.innerHTML;
        \\tempApp.dispose();
        \\tempRoot.remove();
        \\
        \\// Put serverHtml in a new root to simulate SSR
        \\const root = document.createElement('main');
        \\root.innerHTML = serverHtml;
        \\document.body.append(root);
        \\
        \\const existingInput = root.querySelector('#name');
        \\const existingCounter = root.querySelector('.counter');
        \\existingInput.focus();
        \\existingInput.value = 'Pre-hydrated Typing';
        \\
        \\// Boot with worker: true and hydrate: true
        \\const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true, hydrate: true });
        \\
        \\const inputSame = root.querySelector('#name') === existingInput;
        \\const counterSame = root.querySelector('.counter') === existingCounter;
        \\const focusRetained = document.activeElement === existingInput;
        \\const textRetained = existingInput.value === 'Pre-hydrated Typing';
        \\
        \\// Perform action through worker
        \\app.dispatch({ action: 1 });
        \\await new Promise(r => setTimeout(r, 60));
        \\
        \\const countUpdated = root.querySelector('.counter output')?.textContent === '1';
        \\
        \\app.dispose();
        \\root.remove();
        \\
        \\assert.ok(inputSame && counterSame && focusRetained && textRetained && countUpdated);
        \\return true;
    );
}
