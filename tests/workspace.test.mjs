import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdir, readFile, stat } from 'node:fs/promises';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

const directory = new URL('../zig-out/web', import.meta.url).pathname;

test('workspace edits, filters and reorders retained controls through the real WASM host', async () => {
  const server = await serve({ directory });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
    await page.goto(server.url);
    await page.waitForFunction(() => window.workspace);
    assert.equal(await page.locator('tbody tr').count(), 8);
    assert.equal(await page.locator('.metric-value').first().textContent(), '38%');
    assert.equal(await page.getByLabel('Task name', { exact: true }).inputValue(), 'Build the component library');
    await page.getByLabel('Task name', { exact: true }).fill('Reusable controls <&> 🧭');
    await page.getByLabel('Notes', { exact: true }).fill('\nKeep this draft and its selection.');
    assert.equal(await page.locator('[data-task="3"] .task-title > span').textContent(), 'Reusable controls <&> 🧭');
    const retained = await page.evaluate(() => {
      const table = document.querySelector('table'), body = table.tBodies[0];
      const row = document.querySelector('[data-task="3"]'), ancestor = document.querySelector('main');
      const input = document.querySelector('#task-notes'), detail = input.closest('aside');
      input.focus(); input.setSelectionRange(2, 8);
      window.workspace.dispatch({ action: 6 });
      window.workspace.dispatch({ action: 8 });
      window.workspace.setInput({ kind: 4, value: 'done' });
      const ids = [...document.querySelectorAll('[data-node-id]')].map(node => node.dataset.nodeId);
      return table === document.querySelector('table') && body === table.tBodies[0]
        && row === document.querySelector('[data-task="3"]') && body.children[1] === row
        && ancestor === document.querySelector('main') && detail === input.closest('aside')
        && input === document.activeElement && input.value === '\nKeep this draft and its selection.'
        && input.selectionStart === 2 && input.selectionEnd === 8 && new Set(ids).size === ids.length;
    });
    assert.equal(retained, true);
    assert.equal(await page.locator('.metric-value').first().textContent(), '50%');
    assert.equal(await page.locator('.workspace').getAttribute('data-theme'), 'dark');
    await page.getByRole('button', { name: 'In progress', exact: true }).click();
    assert.equal(await page.locator('tbody tr').count(), 2);
    await page.getByLabel('Find a task').fill('no matching task');
    assert.equal(await page.locator('tbody tr').count(), 0);
    assert.equal(await page.getByText('No tasks here yet').isVisible(), true);
    await page.getByRole('button', { name: 'Clear filters', exact: true }).click();
    assert.equal(await page.locator('tbody tr').count(), 8);
    assert.equal(await page.getByLabel('Find a task').inputValue(), '');
    await page.getByLabel('Sort tasks').selectOption('priority');
    assert.equal(await page.locator('tbody tr').first().getAttribute('data-task'), '3');
    await page.getByLabel('Sort tasks').selectOption('title');
    assert.equal(await page.locator('tbody tr').first().getAttribute('data-task'), '7');
    await page.getByRole('button', { name: 'Add task', exact: true }).click();
    assert.equal(await page.locator('tbody tr').count(), 9);
    assert.equal(await page.getByLabel('Task name', { exact: true }).inputValue(), 'Untitled task');
    assert.equal(await page.getByLabel('Task name', { exact: true }).evaluate(node => node === document.activeElement), true);
    await page.getByLabel('Task name', { exact: true }).fill('Review motion details');
    await page.getByLabel('Priority', { exact: true }).selectOption('low');
    await page.getByLabel('Assignee', { exact: true }).selectOption('1');
    assert.equal(await page.locator('[data-task="9"] .priority').textContent(), 'Low');
    assert.equal(await page.locator('[data-task="9"] .avatar').getAttribute('title'), 'Jules Lee');
    await page.getByRole('button', { name: 'Delete task', exact: true }).click();
    assert.equal(await page.locator('tbody tr').count(), 8);
    assert.equal(await page.locator('[data-task="9"]').count(), 0);
    assert.match(await page.locator('.activity-list').textContent(), /Removed a task/);
    await page.getByRole('button', { name: 'Reset demo', exact: true }).click();
    assert.equal(await page.getByLabel('Task name', { exact: true }).inputValue(), 'Build the component library');
    assert.equal(await page.locator('.metric-value').first().textContent(), '38%');
    await page.getByRole('button', { name: 'Use light theme', exact: true }).click();
    await page.locator('[data-task="3"]').getByRole('button', { name: 'Complete task' }).click();
    assert.equal(await page.getByLabel('Status', { exact: true }).inputValue(), 'done');
    await page.locator('[data-task="3"]').getByRole('button', { name: 'Reopen task' }).click();
    assert.equal(await page.getByLabel('Status', { exact: true }).inputValue(), 'planned');
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});

test('workspace capacity, mobile navigation, source links and static subpaths work', async () => {
  // Serving the parent directory exercises assets beneath /web/ like a repository site.
  const server = await serve({ directory: new URL('../zig-out', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 390, height: 844 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(server.url + '/web/index.html');
    await page.waitForFunction(() => window.workspace);
    await page.locator('[data-task="4"] .task-title').click();
    await page.waitForFunction(() => {
      const top = document.querySelector('.detail-panel').getBoundingClientRect().top;
      return top >= 0 && top < 80;
    });
    assert.equal(await page.getByLabel('Task name', { exact: true }).inputValue(), 'Design the landing page');
    assert.equal(await page.getByLabel('Task name', { exact: true }).evaluate(node => {
      const box = node.getBoundingClientRect();
      return document.activeElement === node && box.top >= 0 && box.bottom <= innerHeight;
    }), true);
    await page.getByLabel('Notes', { exact: true }).fill('Keyboard-friendly notes 🧭');
    await page.getByLabel('Notes', { exact: true }).press('Tab');
    assert.equal(await page.evaluate(() => document.activeElement.tagName), 'BUTTON');
    await page.getByRole('button', { name: 'Back to tasks', exact: true }).click();
    assert.equal(await page.locator('[data-task="4"] .task-title').evaluate(node => {
      const box = node.getBoundingClientRect();
      return node === document.activeElement && box.top >= 0 && box.bottom <= innerHeight;
    }), true);
    await page.locator('[data-task="4"] .task-title').press('Enter');
    await page.waitForFunction(() => document.querySelector('.detail-panel').getBoundingClientRect().top < 80);
    assert.equal(await page.getByLabel('Notes', { exact: true }).inputValue(), 'Keyboard-friendly notes 🧭');
    await page.getByLabel('Find a task').fill('no matching task');
    await page.getByRole('button', { name: 'Back to tasks', exact: true }).click();
    assert.equal(await page.getByLabel('Find a task').evaluate(node => node === document.activeElement), true);
    assert.equal(await page.getByLabel('Find a task').inputValue(), 'no matching task');
    await page.getByRole('button', { name: 'Clear filters', exact: true }).click();
    await page.evaluate(() => { for (let i = 0; i < 30; i++) window.workspace.dispatch({ action: 4 }); });
    assert.equal(await page.locator('tbody tr').count(), 24);
    assert.equal(await page.getByRole('button', { name: 'Add task', exact: true }).isDisabled(), true);
    await page.evaluate(() => { for (let i = 0; i < 24; i++) window.workspace.dispatch({ action: 5 }); });
    assert.equal(await page.locator('tbody tr').count(), 0);
    assert.equal(await page.getByText('A fresh start', { exact: true }).isVisible(), true);
    await page.getByRole('button', { name: 'Add your first task', exact: true }).click();
    assert.equal(await page.locator('tbody tr').count(), 1);
    await page.getByRole('button', { name: 'Reset demo', exact: true }).click();
    await page.evaluate(() => { document.documentElement.style.scrollBehavior = 'auto'; document.activeElement.blur(); window.scrollTo(0, 0); });
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
    await mkdir(new URL('../test-results', import.meta.url), { recursive: true });
    await page.screenshot({ path: new URL('../test-results/workspace-mobile.png', import.meta.url).pathname, fullPage: true });
    await page.setViewportSize({ width: 1440, height: 1100 });
    await page.screenshot({ path: new URL('../test-results/workspace-desktop.png', import.meta.url).pathname, fullPage: true });
    await page.getByRole('button', { name: 'Use dark theme' }).click();
    await page.screenshot({ path: new URL('../test-results/workspace-dark.png', import.meta.url).pathname, fullPage: true });
    await page.locator('#how summary').click();
    await page.getByRole('link', { name: 'Read the source walkthrough' }).click();
    assert.equal(await page.title(), 'Inside Fieldwork — zg-gui');
    for (const name of ['workspace.zig', 'workspace.gui.html', 'workspace-metric.gui.html', 'demo.zig', 'demo.gui.html', 'controls.gui.html', 'panels.gui.html']) {
      const response = await page.request.get(server.url + '/web/source/' + name);
      assert.equal(response.status(), 200);
      assert.ok((await response.body()).length > 100);
    }
    await page.getByRole('link', { name: 'The basics demo' }).click();
    await page.waitForFunction(() => window.demo);
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});

test('workspace font controls scale text without losing edits, identity or focus', async () => {
  const server = await serve({ directory });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1100 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(server.url);
    await page.waitForFunction(() => window.workspace);
    const increase = page.getByRole('button', { name: 'Increase font size', exact: true });
    const decrease = page.getByRole('button', { name: 'Decrease font size', exact: true });
    const size = page.getByLabel('Font size', { exact: true });
    const fontSizes = () => page.evaluate(() => ['h1', '.task-title > span', '#task-notes']
      .map(selector => parseFloat(getComputedStyle(document.querySelector(selector)).fontSize)));
    const originalSizes = await fontSizes();
    await increase.focus();
    await increase.press('Enter');
    assert.equal(await size.textContent(), '110%');
    assert.equal(await increase.evaluate(node => node === document.activeElement), true);
    const enlargedSizes = await fontSizes();
    enlargedSizes.forEach((value, index) => assert.ok(Math.abs(value / originalSizes[index] - 1.1) < 0.001));
    await page.getByLabel('Notes', { exact: true }).fill('Keep this draft and selection.');
    assert.equal(await page.evaluate(() => {
      const selectors = ['.workspace', 'main', 'table', 'tbody', '[data-task="3"]', '#task-notes'];
      const retained = selectors.map(selector => document.querySelector(selector));
      const notes = retained.at(-1);
      notes.focus(); notes.setSelectionRange(2, 8);
      window.workspace.dispatch({ action: 12 });
      return selectors.every((selector, index) => document.querySelector(selector) === retained[index])
        && notes === document.activeElement && notes.selectionStart === 2 && notes.selectionEnd === 8
        && notes.value === 'Keep this draft and selection.';
    }), true);
    await increase.click();
    await increase.click();
    assert.equal(await size.textContent(), '140%');
    assert.equal(await increase.isDisabled(), true);
    await page.getByRole('button', { name: 'Reset demo', exact: true }).click();
    assert.equal(await size.textContent(), '140%');
    for (const width of [1440, 1024, 768, 390, 320]) {
      await page.setViewportSize({ width, height: 900 });
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `overflow at ${width}px`);
      assert.equal(await decrease.isVisible(), true);
    }
    await mkdir(new URL('../test-results', import.meta.url), { recursive: true });
    await page.screenshot({ path: new URL('../test-results/workspace-large-text-mobile.png', import.meta.url).pathname, fullPage: true });
    for (let i = 0; i < 6; i++) await decrease.click();
    assert.equal(await size.textContent(), '80%');
    assert.equal(await decrease.isDisabled(), true);
    await page.reload();
    await page.waitForFunction(() => window.workspace);
    assert.equal(await size.textContent(), '80%');
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});

test('workspace artifact reports bounded memory and patch work', async () => {
  const file = new URL('../zig-out/web/workspace.wasm', import.meta.url);
  const { instance } = await WebAssembly.instantiate(await readFile(file));
  const wasm = instance.exports;
  const initialMemory = wasm.memory.buffer.byteLength;
  const initialHtml = wasm.init();
  const decoder = new TextDecoder();
  const read = length => decoder.decode(new Uint8Array(wasm.memory.buffer, wasm.getRenderBuffer(), length));
  const length = wasm.dispatch(6, 0);
  const patch = read(length);
  assert.match(patch, /^M\t/m);
  assert.doesNotMatch(patch, /^[HJ]\t/m);
  for (let i = 0; i < 30; i++) wasm.dispatch(4, 0);
  assert.ok(wasm.resync() > 0);
  assert.equal(wasm.memory.buffer.byteLength, initialMemory);
  console.log(JSON.stringify({ workspaceWasmBytes: (await stat(file)).size, initialMemoryBytes: initialMemory,
    observedMemoryBytes: wasm.memory.buffer.byteLength, initialHtmlBytes: initialHtml,
    reorderPatchBytes: length, reorderCommands: patch.trim().split('\n').length }));
});
