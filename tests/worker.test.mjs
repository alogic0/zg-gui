import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { chromium, firefox } from 'playwright';
import { serve } from '../tools/server.mjs';
import { createProjectionRunner } from '../web/projection-worker.js';

const browserEngines = { chromium, firefox };
const engineName = (process.env.ZG_BROWSER || 'chromium').toLowerCase();
const browserType = browserEngines[engineName] || chromium;

test('zero-copy double-buffering recycling preserves bounded pool size across 10,000+ transfers', async () => {
  const wasmBytes = await readFile(new URL('../zig-out/web/demo.wasm', import.meta.url));
  const wasmModule = await WebAssembly.compile(wasmBytes);

  let renderCount = 0;
  let lastBuffer = null;
  const uniqueBuffers = new Set();

  const runner = createProjectionRunner({
    postMessage: (msg, transfer) => {
      if (msg.type === 'render') {
        renderCount++;
        assert.ok(msg.buffer instanceof ArrayBuffer);
        assert.ok(transfer && transfer.includes(msg.buffer));
        lastBuffer = msg.buffer;
        uniqueBuffers.add(msg.buffer);
      }
    }
  });

  await runner.handleMessage({ type: 'init', wasmModule });
  assert.equal(renderCount, 1);
  assert.ok(lastBuffer);

  // Return initial buffer
  await runner.handleMessage({ type: 'recycle', buffer: lastBuffer });

  // Run 10,000 state transitions alternating actions
  for (let i = 0; i < 10000; i++) {
    // Action 1 is increment, Action 4 is decrement
    await runner.handleMessage({ type: 'dispatch', action: (i % 2 === 0 ? 1 : 4), value: 0 });
    assert.ok(lastBuffer);
    // Recycle buffer back zero-copy
    await runner.handleMessage({ type: 'recycle', buffer: lastBuffer });
  }

  assert.equal(renderCount, 10001);
  // Under double-buffering with immediate recycle, the pool never creates unbounded buffers
  assert.ok(runner.getPoolSize() <= 2, `Pool size should be <= 2, got ${runner.getPoolSize()}`);
  assert.ok(uniqueBuffers.size <= 4, `Unique buffers created should be <= 4, got ${uniqueBuffers.size}`);
  runner.dispose();
});

test('identical DOM projection between worker-based host and main-thread runtime', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await browserType.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/basics.html');

    const match = await page.evaluate(async () => {
      const { createApp, load } = await import('/runtime.js');

      const workerRoot = document.createElement('div');
      const mainRoot = document.createElement('div');
      document.body.append(workerRoot, mainRoot);

      const workerApp = await createApp({ root: workerRoot, wasmUrl: '/demo.wasm', worker: true });
      const mainApp = await load({ root: mainRoot, url: '/demo.wasm' });

      // Compare initial projections
      if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        throw new Error('Initial projections do not match');
      }

      // Execute a sequence of mutations on both
      // 1: Increment counter
      workerApp.dispatch({ action: 1 });
      mainApp.dispatch({ action: 1 });
      // Allow worker message tick
      await new Promise(r => setTimeout(r, 50));
      if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        throw new Error('Projections mismatch after increment');
      }

      // 2: Open details (action 2)
      workerApp.dispatch({ action: 2 });
      mainApp.dispatch({ action: 2 });
      await new Promise(r => setTimeout(r, 50));
      if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        throw new Error('Projections mismatch after details toggle');
      }

      // 3: Input name
      workerApp.setInput({ kind: 1, value: 'Worker Projection' });
      mainApp.setInput({ kind: 1, value: 'Worker Projection' });
      await new Promise(r => setTimeout(r, 50));
      if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        throw new Error('Projections mismatch after setInput');
      }

      // 4: Toggle theme (action 7)
      workerApp.dispatch({ action: 7 });
      mainApp.dispatch({ action: 7 });
      await new Promise(r => setTimeout(r, 50));
      if (workerRoot.innerHTML !== mainRoot.innerHTML) {
        throw new Error('Projections mismatch after theme toggle');
      }

      workerApp.dispose();
      mainApp.dispose();
      workerRoot.remove();
      mainRoot.remove();
      return true;
    });

    assert.equal(match, true);
  } finally {
    if (browser) await browser.close();
    if (server) await server.close();
  }
});

test('Web Worker offscreen projection preserves user typing and optimistic draft', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await browserType.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/basics.html');

    const result = await page.evaluate(async () => {
      const { createApp } = await import('/runtime.js');
      const root = document.createElement('main');
      document.body.append(root);

      const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true });
      const nameInput = root.querySelector('#name');
      if (!nameInput) throw new Error('#name input not found');

      nameInput.focus();
      nameInput.value = 'Optimistic Worker Value';
      nameInput.dispatchEvent(new Event('input', { bubbles: true }));

      // Give worker time to respond with patch
      await new Promise(r => setTimeout(r, 80));

      const inputRetained = (document.activeElement === nameInput)
        && (nameInput.value === 'Optimistic Worker Value')
        && (root.querySelector('#greeting')?.textContent === 'Optimistic Worker Value');

      app.dispose();
      root.remove();
      return inputRetained;
    });

    assert.equal(result, true);
  } finally {
    if (browser) await browser.close();
    if (server) await server.close();
  }
});

test('high-frequency state sweep (60 FPS burst) under worker execution', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await browserType.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/basics.html');

    const finalCount = await page.evaluate(async () => {
      const { createApp } = await import('/runtime.js');
      const root = document.createElement('main');
      document.body.append(root);

      const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true });

      // Dispatch 60 actions rapidly
      for (let i = 0; i < 60; i++) {
        app.dispatch({ action: 1 });
      }

      // Wait for worker queue to settle
      await new Promise(r => setTimeout(r, 200));

      const countText = root.querySelector('.counter output')?.textContent;
      app.dispose();
      root.remove();
      return countText;
    });

    assert.equal(finalCount, '60');
  } finally {
    if (browser) await browser.close();
    if (server) await server.close();
  }
});

test('createApp falls back to main-thread execution when Worker is unavailable', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await browserType.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/basics.html');

    const fallbackSuccess = await page.evaluate(async () => {
      const originalWorker = window.Worker;
      try {
        // Disable Worker on window to test fallback branch
        window.Worker = undefined;
        const { createApp } = await import('/runtime.js');
        const root = document.createElement('main');
        document.body.append(root);

        const app = await createApp({ root, wasmUrl: '/demo.wasm', worker: true });
        const initialCount = root.querySelector('.counter output')?.textContent;

        app.dispatch({ action: 1 });
        const incrementedCount = root.querySelector('.counter output')?.textContent;

        app.dispose();
        root.remove();
        return initialCount === '0' && incrementedCount === '1';
      } finally {
        window.Worker = originalWorker;
      }
    });

    assert.equal(fallbackSuccess, true);
  } finally {
    if (browser) await browser.close();
    if (server) await server.close();
  }
});
