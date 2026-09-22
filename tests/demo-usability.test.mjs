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
      if (file === 'source.html') continue;
      for (const dark of [false, true]) {
        if (dark) await page.getByRole('button', { name: file === 'index.html' ? 'Use dark theme' : 'Dark theme', exact: true }).click();
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
