import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdir, stat } from 'node:fs/promises';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

test('standalone WASM application retains state, identity and focus', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
    const failures = [];
    page.on('pageerror', error => failures.push(error.message));
    page.on('console', message => { if (message.type() === 'error') failures.push(message.text()); });
    await page.goto(server.url);
    await page.waitForFunction(() => window.demo);
    await page.getByLabel('Workspace name').fill('Studio 🧭 <test>');
    assert.equal(await page.locator('#greeting').textContent(), 'Studio 🧭 <test>');
    const retained = await page.evaluate(() => {
      const field = document.querySelector('#name');
      const ancestor = document.querySelector('main');
      field.focus(); field.setSelectionRange(2, 5);
      window.demo.dispatch({ action: 1 });
      window.demo.dispatch({ action: 2 });
      window.demo.setInput({ kind: 2, value: 'true' });
      return field === document.querySelector('#name') && field.isConnected && document.activeElement === field
        && field.selectionStart === 2 && field.selectionEnd === 5 && ancestor === document.querySelector('main');
    });
    assert.equal(retained, true);
    assert.equal(await page.locator('output').textContent(), '1');
    await page.getByLabel('Dark theme').uncheck();
    assert.equal(await page.locator('main').getAttribute('data-theme'), 'light');
    await page.getByRole('button', { name: 'Increment', exact: true }).click();
    assert.equal(await page.locator('output').textContent(), '2');
    await page.getByLabel('First row draft').fill('keep this browser draft');
    assert.equal(await page.evaluate(() => {
      const row = document.querySelector('[aria-label="First row draft"]').closest('li');
      const input = row.querySelector('input'); input.focus();
      window.demo.dispatch({ action: 3 });
      window.demo.dispatch({ action: 4 });
      window.demo.dispatch({ action: 4 });
      const ids = Array.from(document.querySelectorAll('[data-node-id]'), node => node.dataset.nodeId);
      return row.isConnected && row === document.querySelector('[aria-label="First row draft"]').closest('li')
        && input === document.activeElement && input.value === 'keep this browser draft'
        && new Set(ids).size === ids.length;
    }), true);
    assert.equal(await page.evaluate(() => {
      try { window.demo.setInput({ kind: 1, value: '🧭'.repeat(33) }); } catch (error) { return error instanceof RangeError; }
      return false;
    }), true);
    assert.equal(await page.locator('#name').inputValue(), 'Studio 🧭 <test>');
    await page.getByRole('button', { name: 'Show / hide details' }).click();
    assert.equal(await page.locator('#details').isVisible(), false);
    await mkdir(new URL('../test-results', import.meta.url), { recursive: true });
    await page.screenshot({ path: new URL('../test-results/demo-desktop.png', import.meta.url).pathname, fullPage: true });
    await page.setViewportSize({ width: 390, height: 844 });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth), true);
    await page.screenshot({ path: new URL('../test-results/demo-mobile.png', import.meta.url).pathname, fullPage: true });
    assert.deepEqual(failures, []);
    assert.equal(await page.evaluate(() => {
      window.demo.dispose();
      document.querySelector('[data-event="1"]').click();
      const unchanged = document.querySelector('output').textContent === '2';
      try { window.demo.dispatch({ action: 1 }); } catch { return unchanged; }
      return false;
    }), true);
    const artifact = await stat(new URL('../zig-out/web/demo.wasm', import.meta.url));
    console.log(`Standalone demo WASM: ${artifact.size} bytes`);
  } finally { await browser?.close(); await server.close(); }
});

test('runtime resynchronizes an invalid patch and can remount after disposal', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url);
    await page.waitForFunction(() => window.demo);
    const result = await page.evaluate(async () => {
      const { mount } = await import('/runtime.js');
      window.demo.dispose();
      const root = document.querySelector('#app');
      const { instance } = await WebAssembly.instantiate(await (await fetch('/demo.wasm')).arrayBuffer());
      const errors = [];
      const gui = mount({ root, wasm: instance.exports, onError: error => errors.push(error.message) });
      let duplicate = false;
      try { mount({ root, wasm: instance.exports }); } catch { duplicate = true; }
      // Deliberately corrupt a leaf to exercise the host's recovery boundary.
      root.querySelector('output').remove();
      gui.dispatch({ action: 1 });
      const recovered = root.querySelector('output').textContent === '1' && errors.length === 1;
      instance.exports.memory.grow(1);
      gui.setInput({ kind: 1, value: 'after memory growth' });
      const freshMemory = root.querySelector('#name').value === 'after memory growth';
      gui.dispose();
      const next = mount({ root, wasm: instance.exports });
      root.querySelector('[data-event="1"]').click();
      const singleHandler = root.querySelector('output').textContent === '1';
      next.dispose();
      return { duplicate, recovered, freshMemory, singleHandler, pages: instance.exports.memory.buffer.byteLength / 65536 };
    });
    assert.equal(result.duplicate && result.recovered && result.freshMemory && result.singleHandler, true);
    console.log(`Demo initial memory: ${result.pages - 1} WASM pages; after test growth: ${result.pages}`);
  } finally { await browser?.close(); await server.close(); }
});

test('invoked components retain table rows, SVG namespaces and controlled select values', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    const failures = [];
    page.on('pageerror', error => failures.push(error.message));
    await page.goto(server.url);
    await page.waitForFunction(() => window.demo);
    const first = page.getByRole('region', { name: 'Primary integration', exact: true });
    const second = page.getByRole('region', { name: 'Secondary integration', exact: true });
    assert.equal(await first.getByRole('combobox').inputValue(), 'email');
    assert.equal(await second.getByRole('combobox').inputValue(), 'email');
    await first.getByRole('combobox').selectOption('sms');
    assert.equal(await second.getByRole('combobox').inputValue(), 'email');
    const independent = await page.evaluate(() => {
      const first = document.querySelector('[aria-label="Primary integration"]');
      const second = document.querySelector('[aria-label="Secondary integration"]');
      const select = first.querySelector('select');
      const input = second.querySelector('input');
      input.value = 'independent browser draft'; input.focus();
      window.demo.setInput({ kind: 3, value: 'email' });
      return first.isConnected && second.isConnected && select === first.querySelector('select')
        && input === second.querySelector('input') && document.activeElement === input
        && input.value === 'independent browser draft' && select.value === 'email'
        && second.querySelector('select').value === 'email';
    });
    assert.equal(independent, true);
    await first.getByRole('combobox').selectOption('email');
    await first.getByRole('textbox', { name: 'First row', exact: true }).fill('retained mapping draft');
    const result = await page.evaluate(() => {
      const panel = document.querySelector('[aria-label="Primary integration"]');
      const row = panel.querySelector('tbody tr');
      const input = row.querySelector('input'); input.focus();
      const select = panel.querySelector('select');
      const markers = panel.querySelector('g');
      const initialCircle = markers.firstElementChild;
      window.demo.dispatch({ action: 3 });
      window.demo.dispatch({ action: 4 });
      const removedSelection = select.value === '';
      const appendedCircle = markers.lastElementChild;
      const svgCorrect = initialCircle.isConnected && markers.children.length === 3
        && appendedCircle.namespaceURI === 'http://www.w3.org/2000/svg'
        && appendedCircle.cx.baseVal.value === 32;
      const rowsCorrect = row.isConnected && input.value === 'retained mapping draft'
        && document.activeElement === input && panel.querySelectorAll('tbody tr').length === 3;
      window.demo.dispatch({ action: 4 });
      const restored = select.value === 'email';
      window.demo.setInput({ kind: 2, value: 'true' });
      const ids = [...document.querySelectorAll('[data-node-id]')].map(n => n.dataset.nodeId);
      return { removedSelection, restored, svgCorrect, rowsCorrect, unique: new Set(ids).size === ids.length,
        icon: panel.querySelector('use').getAttribute('href'), selectRetained: select === panel.querySelector('select') };
    });
    assert.deepEqual(result, { removedSelection: true, restored: true, svgCorrect: true, rowsCorrect: true,
      unique: true, icon: 'icons.svg#link-active', selectRetained: true });
    assert.deepEqual(failures, []);
  } finally { await browser?.close(); await server.close(); }
});
