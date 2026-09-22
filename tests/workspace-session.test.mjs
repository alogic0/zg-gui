import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

const directory = new URL('../zig-out', import.meta.url).pathname;
const key = 'zg-gui.workspace.session:/web/';

test('workspace tasks, drafts and view state survive page navigation and reload', async () => {
  const server = await serve({ directory });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({ viewport: { width: 1440, height: 1100 } });
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(server.url + '/web/index.html');
    await page.waitForFunction(() => window.workspace);
    await page.getByRole('button', { name: 'Add task', exact: true }).click();
    await page.getByLabel('Task name', { exact: true }).fill('Keep this new task 🧭');
    await page.getByLabel('Notes', { exact: true }).fill('Saved notes\n<&> 🧭');
    await page.getByLabel('Status', { exact: true }).selectOption('active');
    await page.getByLabel('Priority', { exact: true }).selectOption('low');
    await page.getByLabel('Assignee', { exact: true }).selectOption('1');
    await page.getByRole('button', { name: 'Move task up', exact: true }).click();
    await page.getByRole('button', { name: 'Increase font size', exact: true }).click();
    const order = await page.locator('tbody tr').evaluateAll(rows => rows.map(row => row.dataset.task));
    const activity = await page.locator('.activity-list').textContent();
    await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name: 'Basics', exact: true }).click();
    await page.waitForFunction(() => window.demo);
    await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name: 'Source', exact: true }).click();
    await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name: 'Showcase', exact: true }).click();
    await page.waitForFunction(() => window.workspace);
    const check = async () => {
      assert.equal(await page.getByLabel('Task name', { exact: true }).inputValue(), 'Keep this new task 🧭');
      assert.equal(await page.getByLabel('Notes', { exact: true }).inputValue(), 'Saved notes\n<&> 🧭');
      assert.equal(await page.getByLabel('Status', { exact: true }).inputValue(), 'active');
      assert.equal(await page.getByLabel('Priority', { exact: true }).inputValue(), 'low');
      assert.equal(await page.getByLabel('Assignee', { exact: true }).inputValue(), '1');
      assert.equal(await page.getByLabel('Font size', { exact: true }).textContent(), '110%');
      assert.equal(await page.locator('.activity-list').textContent(), activity);
      assert.match(await page.locator('[data-save-status]').textContent(), /Saved in this tab/);
    };
    await check();
    assert.deepEqual(await page.locator('tbody tr').evaluateAll(rows => rows.map(row => row.dataset.task)), order);
    assert.equal(await page.locator('tr[data-selected="true"]').getAttribute('data-task'), '9');
    await page.getByRole('button', { name: 'In progress', exact: true }).click();
    await page.getByLabel('Find a task').fill('Keep this');
    await page.getByLabel('Sort tasks').selectOption('priority');
    await page.reload(); await page.waitForFunction(() => window.workspace);
    await check();
    assert.equal(await page.getByLabel('Find a task').inputValue(), 'Keep this');
    assert.equal(await page.getByLabel('Sort tasks').inputValue(), 'priority');
    assert.equal(await page.getByRole('button', { name: 'In progress', exact: true }).getAttribute('aria-pressed'), 'true');
    assert.equal(await page.locator('tbody tr').count(), 1);
    // A separate tab starts a separate workspace rather than sharing task writes.
    const other = await context.newPage();
    await other.goto(server.url + '/web/index.html');
    await other.waitForFunction(() => window.workspace);
    assert.equal(await other.locator('tbody tr').count(), 8);
    await other.close();
    await page.getByRole('button', { name: 'Delete task', exact: true }).click();
    await page.reload(); await page.waitForFunction(() => window.workspace);
    assert.equal(await page.locator('[data-task="9"]').count(), 0);
    await page.getByRole('button', { name: 'Clear filters', exact: true }).click();
    await page.getByRole('button', { name: 'Add task', exact: true }).click();
    assert.equal(await page.locator('tr[data-selected="true"]').getAttribute('data-task'), '10');
    // Empty state is a saved workspace, not an absent snapshot.
    await page.evaluate(() => { for (let i = 0; i < 9; i++) window.workspace.dispatch({ action: 5 }); });
    await page.reload(); await page.waitForFunction(() => window.workspace);
    assert.equal(await page.locator('tbody tr').count(), 0);
    assert.equal(await page.getByText('A fresh start', { exact: true }).isVisible(), true);
    assert.equal(await page.locator('[data-save-status]').isVisible(), true);
    await page.getByRole('button', { name: 'Reset demo', exact: true }).click();
    await page.reload(); await page.waitForFunction(() => window.workspace);
    assert.equal(await page.locator('tbody tr').count(), 8);
    assert.equal(await page.getByLabel('Task name', { exact: true }).inputValue(), 'Build the component library');
    // Moving filtered-out rows may commit with an empty DOM patch; save it too.
    await page.locator('[data-task="5"] .task-title').click();
    await page.getByRole('button', { name: 'Done', exact: true }).click();
    await page.getByRole('button', { name: 'Move task up', exact: true }).click();
    await page.getByRole('button', { name: 'Move task up', exact: true }).click();
    await page.reload(); await page.waitForFunction(() => window.workspace);
    await page.getByRole('button', { name: 'All tasks', exact: true }).click();
    assert.equal(await page.locator('tbody tr').nth(2).getAttribute('data-task'), '5');
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});

test('invalid snapshots and unavailable storage leave a usable workspace with honest feedback', async () => {
  const server = await serve({ directory });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(server.url + '/web/index.html');
    await page.waitForFunction(() => window.workspace);
    for (const saved of ['%%%broken', 'AAAA', 'x'.repeat(50000)]) {
      await page.evaluate(({ key, saved }) => sessionStorage.setItem(key, saved), { key, saved });
      await page.reload(); await page.waitForFunction(() => window.workspace);
      assert.equal(await page.locator('tbody tr').count(), 8);
      assert.match(await page.locator('[data-save-status]').textContent(), /could not be restored/);
    }
    // A restored session at capacity must retain all fields and continue editing.
    await page.evaluate(() => {
      for (let i = 0; i < 16; i++) window.workspace.dispatch({ action: 4 });
      window.workspace.setInput({ kind: 2, value: '🧭'.repeat(24) });
      window.workspace.setInput({ kind: 3, value: '🧭'.repeat(128) });
    });
    await page.reload(); await page.waitForFunction(() => window.workspace);
    assert.equal(await page.locator('tbody tr').count(), 24);
    assert.equal(await page.getByRole('button', { name: 'Add task', exact: true }).isDisabled(), true);
    assert.equal(await page.getByLabel('Notes', { exact: true }).inputValue(), '🧭'.repeat(128));
    for (const failure of ['denied', 'quota']) {
      const context = await browser.newContext();
      await context.addInitScript(failure => {
        if (failure === 'denied') Object.defineProperty(window, 'sessionStorage', { get() { throw new DOMException('Denied', 'SecurityError'); } });
        else Storage.prototype.setItem = () => { throw new DOMException('Full', 'QuotaExceededError'); };
      }, failure);
      const failed = await context.newPage();
      failed.on('pageerror', error => errors.push(error.message));
      await failed.goto(server.url + '/web/index.html');
      await failed.waitForFunction(() => window.workspace);
      await failed.getByRole('button', { name: 'Add task', exact: true }).click();
      await failed.getByLabel('Task name', { exact: true }).fill('Still editable');
      assert.equal(await failed.locator('tbody tr').count(), 9);
      assert.match(await failed.locator('[data-save-status]').textContent(), /Saving unavailable/);
      await context.close();
    }
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});
