import assert from 'node:assert/strict';
import { test } from 'node:test';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

test('demo navigation, readable text and theme contrast work at narrow widths', async () => {
  const server = await serve({ directory: new URL('../zig-out', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 390, height: 844 }, reducedMotion: 'reduce' });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    for (const file of ['index.html', 'basics.html', 'source.html']) {
      await page.goto(server.url + '/web/' + file);
      if (file !== 'source.html') await page.waitForFunction(() => window.workspace || window.demo);
      const nav = page.getByRole('navigation', { name: 'Demo pages', exact: true });
      for (const name of ['Showcase', 'Basics', 'Source']) {
        assert.equal(await nav.getByRole('link', { name, exact: true }).isVisible(), true);
      }
      for (const width of [1440, 768, 390, 320]) {
        await page.setViewportSize({ width, height: 900 });
        assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `${file} at ${width}px`);
      }
      for (const dark of [false, true]) {
        if (await page.locator('html').getAttribute('data-theme') !== (dark ? 'dark' : 'light')) {
          await page.locator('.theme-toggle').click();
        }
        const failures = await page.evaluate(() => {
          const rgb = value => (value.match(/[\d.]+/g) || []).map(Number);
          const luminance = rgb => rgb.slice(0, 3).map(v => v / 255)
            .map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)
            .reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
          const failures = [];
          for (const node of document.querySelectorAll('body *')) {
            if (!node.checkVisibility({ checkVisibilityCSS: true }) || node.closest('button:disabled')
              || node.closest('.brand,.site-brand') || node.tagName === 'OPTION'
              || ![...node.childNodes].some(n => n.nodeType === Node.TEXT_NODE && n.textContent.trim())) continue;
            const style = getComputedStyle(node), foreground = rgb(style.color);
            if (foreground[3] === 0) continue;
            // These demos use opaque solid backgrounds; walk through transparent containers.
            let background = [255, 255, 255];
            for (let parent = node; parent; parent = parent.parentElement) {
              const candidate = rgb(getComputedStyle(parent).backgroundColor);
              if (candidate.length === 3 || candidate[3] === 1) { background = candidate; break; }
            }
            const a = luminance(foreground), b = luminance(background);
            const contrast = (Math.max(a, b) + .05) / (Math.min(a, b) + .05);
            if (contrast < 4.5) failures.push({ text: node.textContent.trim().slice(0, 60), contrast });
          }
          return failures;
        });
        assert.deepEqual(failures, [], `${file}, ${dark ? 'dark' : 'light'} text contrast`);
      }
      if (file === 'index.html') {
        const sizes = await page.evaluate(() => ({
          title: parseFloat(getComputedStyle(document.querySelector('.task-title > span')).fontSize),
          input: parseFloat(getComputedStyle(document.querySelector('#task-notes')).fontSize),
          completion: document.querySelector('.task-check').getBoundingClientRect().width,
          sort: document.querySelector('.sort-control select').getBoundingClientRect().height,
        }));
        assert.ok(sizes.title >= 14 && sizes.input >= 16 && sizes.completion >= 44 && sizes.sort >= 44);
      }
    }
    await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name: 'Basics', exact: true }).click();
    await page.waitForFunction(() => window.demo);
    await page.getByRole('link', { name: 'How input updates work' }).click();
    assert.equal(await page.locator('#basics-state').isVisible(), true);
    await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name: 'Showcase', exact: true }).click();
    await page.waitForFunction(() => window.workspace);
    // Browser navigation listeners are owned by the example and disposed with it.
    assert.equal(await page.evaluate(() => {
      window.workspace.dispose();
      const back = document.querySelector('[data-back-to-tasks]');
      back.focus(); back.click();
      return document.activeElement === back;
    }), true);
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});

test('Basics option removal is explicit and remembers independent choices', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/basics.html');
    await page.waitForFunction(() => window.demo);
    const primary = page.getByRole('region', { name: 'Primary integration', exact: true });
    const secondary = page.getByRole('region', { name: 'Secondary integration', exact: true });
    await secondary.getByRole('combobox').selectOption('sms');
    await page.getByRole('button', { name: 'Toggle third row', exact: true }).click();
    await page.getByRole('button', { name: 'Reverse rows', exact: true }).click();
    assert.deepEqual(await page.locator('.card.wide li label span').allTextContents(), ['Third row', 'Second row', 'First row']);
    assert.equal(await primary.getByRole('combobox').inputValue(), 'email');
    assert.equal(await secondary.getByRole('combobox').inputValue(), 'sms');
    await page.getByRole('button', { name: 'Remove Email option', exact: true }).click();
    assert.equal(await primary.getByRole('combobox').inputValue(), '');
    assert.equal(await primary.getByRole('status').isVisible(), true);
    assert.equal(await secondary.getByRole('combobox').inputValue(), 'sms');
    assert.equal(await secondary.getByRole('status').isVisible(), false);
    await page.getByRole('button', { name: 'Restore Email option', exact: true }).click();
    assert.equal(await primary.getByRole('combobox').inputValue(), 'email');
    assert.equal(await secondary.getByRole('combobox').inputValue(), 'sms');
    await page.getByRole('button', { name: 'Remove Email option', exact: true }).click();
    await primary.getByRole('combobox').selectOption('sms');
    await page.getByRole('button', { name: 'Restore Email option', exact: true }).click();
    assert.equal(await primary.getByRole('combobox').inputValue(), 'sms');
  } finally { await browser?.close(); await server.close(); }
});

test('whole task rows remain selectable after edits, sorting, filtering and reset', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ viewport: { width: 1440, height: 1100 }, reducedMotion: 'reduce' });
    await page.goto(server.url);
    await page.waitForFunction(() => window.workspace);
    await page.evaluate(() => {
      window.retained = ['main', 'table', 'tbody', '.detail-panel', '#task-title', '[data-task="5"]']
        .map(selector => [selector, document.querySelector(selector)]);
    });
    const select = async (id, target) => {
      await page.locator(`[data-task="${id}"] ${target}`).click();
      assert.equal(await page.locator('tr[data-selected="true"]').getAttribute('data-task'), String(id));
      assert.equal(await page.locator('#task-title').evaluate(node => node === document.activeElement), true);
    };
    await select(5, '.status-badge');
    await page.locator('#task-title').fill('Edited task');
    await page.locator('#task-notes').fill('Retain this draft');
    await select(4, '.priority svg');
    await select(5, '.avatar');
    assert.equal(await page.locator('#task-title').inputValue(), 'Edited task');
    assert.equal(await page.locator('#task-notes').inputValue(), 'Retain this draft');
    // Hit the empty left gutter of a different row, outside either button.
    await page.locator('[data-task="6"]').click({ position: { x: 3, y: 3 } });
    assert.equal(await page.locator('tr[data-selected="true"]').getAttribute('data-task'), '6');
    // Nested completion must neither select that row nor toggle twice.
    await page.locator('[data-task="4"] .task-check').click();
    assert.equal(await page.locator('tr[data-selected="true"]').getAttribute('data-task'), '6');
    assert.equal(await page.locator('[data-task="4"]').getAttribute('data-status'), 'done');
    await page.locator('[data-task="5"] .task-title').focus();
    await page.keyboard.press('Enter');
    await page.getByRole('button', { name: 'Move task up', exact: true }).click();
    await page.getByLabel('Sort tasks').selectOption('title');
    await select(6, '.status-badge');
    await select(5, '.status-badge');
    assert.equal(await page.evaluate(() => window.retained.every(([selector, node]) => document.querySelector(selector) === node)), true);
    await page.getByRole('button', { name: 'To do', exact: true }).click();
    await select(6, '.status-badge');
    await page.getByRole('button', { name: 'All tasks', exact: true }).click();
    await page.getByRole('button', { name: 'Reset demo', exact: true }).click();
    await select(5, '.status-badge');
    await page.setViewportSize({ width: 390, height: 844 });
    await select(4, '.status-badge');
    await page.waitForFunction(() => {
      const top = document.querySelector('.detail-panel').getBoundingClientRect().top;
      return top >= 0 && top < 80;
    });
    await page.getByRole('button', { name: 'Back to tasks', exact: true }).click();
    assert.equal(await page.locator('[data-task="4"] .task-title').evaluate(node => node === document.activeElement), true);
  } finally { await browser?.close(); await server.close(); }
});

test('theme persists across every demo page, reload and tabs, with safe storage fallback', async () => {
  const server = await serve({ directory: new URL('../zig-out', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    const ready = async () => {
      await page.waitForFunction(() => window.workspace || window.demo || document.querySelector('[data-source-theme]'));
    };
    const checkTheme = async theme => {
      await page.waitForFunction(theme => document.documentElement.dataset.theme === theme
        && [...document.querySelectorAll('#app [data-theme]')].every(node => node.dataset.theme === theme), theme);
      assert.equal(await page.locator('.theme-toggle').textContent(), theme === 'dark' ? 'Light theme' : 'Dark theme');
    };
    await page.goto(server.url + '/web/index.html');
    await ready();
    await page.locator('.theme-toggle').click();
    await checkTheme('dark');
    for (const name of ['Basics', 'Source', 'Showcase']) {
      await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name, exact: true }).click();
      await ready(); await checkTheme('dark');
      await page.reload(); await ready(); await checkTheme('dark');
    }
    await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name: 'Source', exact: true }).click();
    await ready();
    await page.locator('.theme-toggle').click();
    await checkTheme('light');
    await page.goBack(); await ready(); await checkTheme('light');
    await page.goForward(); await ready(); await checkTheme('light');
    for (const name of ['Basics', 'Showcase', 'Source']) {
      await page.getByRole('navigation', { name: 'Demo pages' }).getByRole('link', { name, exact: true }).click();
      await ready(); await checkTheme('light');
    }
    const other = await context.newPage();
    other.on('pageerror', error => errors.push(error.message));
    await other.goto(server.url + '/web/basics.html');
    await other.waitForFunction(() => window.demo);
    await other.locator('.theme-toggle').click();
    await checkTheme('dark');
    await page.locator('.theme-toggle').click();
    await other.waitForFunction(() => document.querySelector('.demo').dataset.theme === 'light');
    // Storage events must not dispatch into an app after disposal.
    await other.evaluate(() => window.demo.dispose());
    await page.locator('.theme-toggle').click();
    await other.waitForTimeout(50);
    assert.equal(await other.locator('.demo').getAttribute('data-theme'), 'light');
    await page.evaluate(() => localStorage.setItem('zg-gui.demo.theme', 'invalid'));
    await page.reload(); await ready(); await checkTheme('light');
    await page.addInitScript(() => {
      Object.defineProperty(window, 'localStorage', { get() { throw new DOMException('Unavailable', 'SecurityError'); } });
    });
    for (const file of ['index.html', 'basics.html', 'source.html']) {
      await page.goto(server.url + '/web/' + file); await ready();
      await checkTheme('light');
      await page.locator('.theme-toggle').click(); await checkTheme('dark');
      await page.locator('.theme-toggle').click(); await checkTheme('light');
    }
    assert.deepEqual(errors, []);
  } finally { await browser?.close(); await server.close(); }
});

test('control graphics scale within padded targets at every layout and supported text size', async () => {
  const server = await serve({ directory: new URL('../zig-out/web', import.meta.url).pathname });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage({ reducedMotion: 'reduce' });
    await page.goto(server.url);
    await page.waitForFunction(() => window.workspace);
    for (const scale of [80, 100, 140]) {
      await page.evaluate(scale => {
        for (let i = 0; i < 6; i++) window.workspace.dispatch({ action: 11 });
        for (let i = 80; i < scale; i += 10) window.workspace.dispatch({ action: 12 });
      }, scale);
      for (const width of [1440, 768, 390, 320]) {
        await page.setViewportSize({ width, height: 900 });
        const failures = await page.evaluate(() => {
          const failures = [];
          if (document.documentElement.scrollWidth > innerWidth) failures.push('page overflow');
          for (const button of document.querySelectorAll('.detail-actions .icon-button')) {
            const box = button.getBoundingClientRect(), icon = button.querySelector('svg').getBoundingClientRect();
            if (box.width < 44 || box.height < 44 || icon.width < 16 || icon.width > 28.1
              || Math.abs(icon.width - icon.height) > .1 || icon.left - box.left < 7 || box.right - icon.right < 7
              || icon.top - box.top < 7 || box.bottom - icon.bottom < 7) failures.push('arrow size/padding');
          }
          for (const icon of document.querySelectorAll('.workspace svg.icon')) {
            if (!icon.checkVisibility()) continue;
            const box = icon.getBoundingClientRect();
            if (Math.abs(box.width - box.height) > .1) failures.push('distorted icon');
            const panel = icon.closest('.panel');
            if (panel) {
              const bounds = panel.getBoundingClientRect();
              if (box.left < bounds.left + 8 || box.right > bounds.right - 8) failures.push('icon near panel edge');
            }
          }
          for (const select of document.querySelectorAll('select')) {
            const style = getComputedStyle(select);
            if (parseFloat(style.paddingRight) < 36 || parseFloat(style.paddingLeft) < 12) failures.push('select arrow clearance');
          }
          return failures;
        });
        assert.deepEqual(failures, [], `${width}px at ${scale}%`);
      }
    }
  } finally { await browser?.close(); await server.close(); }
});
