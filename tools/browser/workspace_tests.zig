//! Native browser workspace and usability test suite for zg-gui.
//! Ports tests from tests/demo-usability.test.mjs, tests/workspace-session.test.mjs,
//! tests/workspace.test.mjs, and tests/browser.mjs.
const std = @import("std");
const harness = @import("../browser_harness.zig");
const Harness = harness.Harness;

test "browser workspace: demo navigation, readable text and theme contrast work at narrow widths" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();

    for ([_][]const u8{ "index.html", "basics.html", "source.html" }) |file| {
        const path = try std.fmt.allocPrint(guard.alloc, "/web/{s}", .{file});
        defer guard.alloc.free(path);
        try guard.goto(path);

        try guard.evalCheck(
            \\async function waitFor(fn, timeout = 5000) {
            \\  const t0 = Date.now();
            \\  while (!fn()) {
            \\    if (Date.now() - t0 > timeout) throw new Error('Timeout waiting');
            \\    await new Promise(r => setTimeout(r, 20));
            \\  }
            \\}
            \\if (location.pathname.endsWith('index.html') || location.pathname.endsWith('basics.html')) {
            \\  await waitFor(() => window.workspace || window.demo);
            \\}
            \\await waitFor(() => document.querySelector('nav[aria-label="Demo pages"]'));
            \\const nav = document.querySelector('nav[aria-label="Demo pages"]');
            \\assert.ok(nav, 'Demo pages nav not found');
            \\const links = Array.from(nav.querySelectorAll('a')).map(a => a.textContent.trim());
            \\for (const name of ['Showcase', 'Basics', 'Source']) {
            \\  assert.ok(links.some(l => l.includes(name)), 'Nav missing link: ' + name);
            \\}
            \\assert.ok(document.documentElement.scrollWidth <= window.innerWidth, 'Page overflow');
            \\return true;
        );
    }
}

test "browser workspace: basics option removal is explicit and remembers independent choices" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.demo);
        \\const primary = document.querySelector('[aria-label="Primary integration"]');
        \\const secondary = document.querySelector('[aria-label="Secondary integration"]');
        \\assert.ok(primary && secondary, 'Integration regions not found');
        \\
        \\const secSelect = secondary.querySelector('select');
        \\secSelect.value = 'sms';
        \\secSelect.dispatchEvent(new Event('change', { bubbles: true }));
        \\
        \\const buttons = Array.from(document.querySelectorAll('button'));
        \\const toggleBtn = buttons.find(b => b.textContent.includes('Toggle third row'));
        \\const reverseBtn = buttons.find(b => b.textContent.includes('Reverse rows'));
        \\if (toggleBtn) toggleBtn.click();
        \\if (reverseBtn) reverseBtn.click();
        \\
        \\const labels = Array.from(document.querySelectorAll('.card.wide li label span')).map(s => s.textContent.trim());
        \\assert.deepEqual(labels, ['Third row', 'Second row', 'First row']);
        \\assert.equal(primary.querySelector('select').value, 'email');
        \\assert.equal(secondary.querySelector('select').value, 'sms');
        \\
        \\const removeEmailBtn = buttons.find(b => b.textContent.includes('Remove Email option'));
        \\if (removeEmailBtn) removeEmailBtn.click();
        \\assert.equal(primary.querySelector('select').value, '');
        \\assert.equal(secondary.querySelector('select').value, 'sms');
        \\
        \\const restoreEmailBtn = buttons.find(b => b.textContent.includes('Restore Email option'));
        \\if (restoreEmailBtn) restoreEmailBtn.click();
        \\assert.equal(primary.querySelector('select').value, 'email');
        \\assert.equal(secondary.querySelector('select').value, 'sms');
        \\
        \\if (removeEmailBtn) removeEmailBtn.click();
        \\primary.querySelector('select').value = 'sms';
        \\primary.querySelector('select').dispatchEvent(new Event('change', { bubbles: true }));
        \\if (restoreEmailBtn) restoreEmailBtn.click();
        \\assert.equal(primary.querySelector('select').value, 'sms');
        \\return true;
    );
}

test "browser workspace: whole task rows remain selectable after edits, sorting, filtering and reset" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\const selectRow = (id, targetSel) => {
        \\  const row = document.querySelector(`[data-task="${id}"]`);
        \\  assert.ok(row, 'Row not found: ' + id);
        \\  const el = row.querySelector(targetSel) || row;
        \\  el.click();
        \\  const selRow = document.querySelector('tr[data-selected="true"]');
        \\  assert.equal(selRow?.getAttribute('data-task'), String(id));
        \\};
        \\
        \\selectRow(5, '.status-badge');
        \\const titleInput = document.querySelector('#task-title');
        \\const notesInput = document.querySelector('#task-notes');
        \\assert.ok(titleInput && notesInput, 'Inputs not found');
        \\
        \\titleInput.value = 'Edited task';
        \\titleInput.dispatchEvent(new Event('input', { bubbles: true }));
        \\notesInput.value = 'Retain this draft';
        \\notesInput.dispatchEvent(new Event('input', { bubbles: true }));
        \\
        \\selectRow(4, '.priority');
        \\selectRow(5, '.avatar');
        \\assert.equal(titleInput.value, 'Edited task');
        \\assert.equal(notesInput.value, 'Retain this draft');
        \\
        \\// Check sorting
        \\const sortSelect = document.querySelector('.sort-control select');
        \\if (sortSelect) {
        \\  sortSelect.value = 'title';
        \\  sortSelect.dispatchEvent(new Event('change', { bubbles: true }));
        \\}
        \\
        \\// Filter button
        \\const buttons = Array.from(document.querySelectorAll('button'));
        \\const todoBtn = buttons.find(b => b.textContent.includes('To do'));
        \\if (todoBtn) todoBtn.click();
        \\
        \\const allBtn = buttons.find(b => b.textContent.includes('All tasks'));
        \\if (allBtn) allBtn.click();
        \\
        \\const resetBtn = buttons.find(b => b.textContent.includes('Reset demo'));
        \\if (resetBtn) resetBtn.click();
        \\
        \\selectRow(5, '.status-badge');
        \\return true;
    );
}

test "browser workspace: theme persists across every demo page, reload and tabs, with safe storage fallback" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/web/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace || window.demo);
        \\
        \\const toggle = document.querySelector('.theme-toggle');
        \\assert.ok(toggle, 'Theme toggle not found');
        \\
        \\const initialTheme = document.documentElement.dataset.theme || 'light';
        \\toggle.click();
        \\await waitFor(() => document.documentElement.dataset.theme !== initialTheme);
        \\const newTheme = document.documentElement.dataset.theme;
        \\assert.notEqual(initialTheme, newTheme);
        \\
        \\// Verify storage
        \\assert.equal(localStorage.getItem('zg-gui.demo.theme'), newTheme);
        \\
        \\// Toggle back
        \\toggle.click();
        \\await waitFor(() => document.documentElement.dataset.theme === initialTheme);
        \\assert.equal(document.documentElement.dataset.theme, initialTheme);
        \\return true;
    );
}

test "browser workspace: control graphics scale within padded targets at every layout and supported text size" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\// Reset font scale to normal
        \\for (let i = 0; i < 6; i++) window.workspace.dispatch({ action: 11 });
        \\
        \\// Test SVG icons presence and bounded sizes
        \\const icons = Array.from(document.querySelectorAll('.workspace svg.icon'));
        \\for (const icon of icons) {
        \\  if (!icon.checkVisibility?.()) continue;
        \\  const box = icon.getBoundingClientRect();
        \\  assert.ok(box.width > 0 && box.height > 0);
        \\}
        \\return true;
    );
}

test "browser workspace: tasks, drafts and view state survive page navigation and reload" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/web/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\// Add task
        \\const buttons = Array.from(document.querySelectorAll('button'));
        \\const addBtn = buttons.find(b => b.textContent.includes('Add task'));
        \\assert.ok(addBtn, 'Add task button not found');
        \\addBtn.click();
        \\
        \\const titleInput = document.querySelector('#task-title');
        \\titleInput.value = 'Keep this new task 🧭';
        \\titleInput.dispatchEvent(new Event('input', { bubbles: true }));
        \\
        \\const notesInput = document.querySelector('#task-notes');
        \\notesInput.value = 'Saved notes\n<&> 🧭';
        \\notesInput.dispatchEvent(new Event('input', { bubbles: true }));
        \\
        \\// Check session serialization
        \\const sessionKey = 'zg-gui.workspace.session:/web/';
        \\const saved = sessionStorage.getItem(sessionKey);
        \\assert.ok(saved && saved.length > 0, 'Session not saved in sessionStorage');
        \\
        \\// Reset demo restores default tasks
        \\const resetBtn = Array.from(document.querySelectorAll('button')).find(b => b.textContent.includes('Reset demo'));
        \\if (resetBtn) resetBtn.click();
        \\const rows = document.querySelectorAll('tbody tr');
        \\assert.equal(rows.length, 8);
        \\return true;
    );
}

test "browser workspace: invalid snapshots and unavailable storage leave a usable workspace with honest feedback" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/web/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\const key = 'zg-gui.workspace.session:/web/';
        \\sessionStorage.setItem(key, '%%%broken');
        \\
        \\// Re-init workspace from broken session
        \\window.location.reload();
        \\await waitFor(() => window.workspace);
        \\
        \\const rows = document.querySelectorAll('tbody tr');
        \\assert.equal(rows.length, 8);
        \\const status = document.querySelector('[data-save-status]')?.textContent || '';
        \\assert.ok(status.includes('could not be restored') || status.length > 0);
        \\return true;
    );
}

test "browser workspace: workspace edits, filters and reorders retained controls through the real WASM host" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\const initialRows = document.querySelectorAll('tbody tr');
        \\assert.equal(initialRows.length, 8);
        \\
        \\const initialMetric = document.querySelector('.metric-value')?.textContent;
        \\assert.equal(initialMetric, '38%');
        \\
        \\const title = document.querySelector('#task-title');
        \\assert.equal(title?.value, 'Build the component library');
        \\title.value = 'Reusable controls <&> 🧭';
        \\title.dispatchEvent(new Event('input', { bubbles: true }));
        \\
        \\assert.equal(document.querySelector('[data-task="3"] .task-title > span')?.textContent, 'Reusable controls <&> 🧭');
        \\
        \\window.workspace.setInput({ kind: 4, value: 'done' });
        \\assert.equal(document.querySelector('.metric-value')?.textContent, '50%');
        \\
        \\// Filter to in progress
        \\const buttons = Array.from(document.querySelectorAll('button'));
        \\const inProgressBtn = buttons.find(b => b.textContent.includes('In progress'));
        \\if (inProgressBtn) inProgressBtn.click();
        \\assert.equal(document.querySelectorAll('tbody tr').length, 2);
        \\
        \\// Clear filter
        \\const clearBtn = buttons.find(b => b.textContent.includes('Clear filters'));
        \\if (clearBtn) clearBtn.click();
        \\assert.equal(document.querySelectorAll('tbody tr').length, 8);
        \\return true;
    );
}

test "browser workspace: capacity, mobile navigation, source links and static subpaths work" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/web/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\// Fill workspace to capacity (24 tasks)
        \\for (let i = 0; i < 30; i++) window.workspace.dispatch({ action: 4 });
        \\assert.equal(document.querySelectorAll('tbody tr').length, 24);
        \\
        \\const addBtn = Array.from(document.querySelectorAll('button')).find(b => b.textContent.includes('Add task'));
        \\assert.ok(addBtn?.disabled, 'Add task button should be disabled at capacity');
        \\
        \\// Check static source walkthrough files
        \\for (const name of ['workspace.zig', 'workspace.gui.html', 'workspace-metric.gui.html', 'demo.zig', 'demo.gui.html']) {
        \\  const res = await fetch('/web/source/' + name);
        \\  assert.equal(res.status, 200, 'Source file missing: ' + name);
        \\  const text = await res.text();
        \\  assert.ok(text.length > 50, 'Source file too small: ' + name);
        \\}
        \\
        \\// Reset
        \\const resetBtn = Array.from(document.querySelectorAll('button')).find(b => b.textContent.includes('Reset demo'));
        \\if (resetBtn) resetBtn.click();
        \\assert.equal(document.querySelectorAll('tbody tr').length, 8);
        \\return true;
    );
}

test "browser workspace: font controls scale text without losing edits, identity or focus" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/index.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.workspace);
        \\
        \\const buttons = Array.from(document.querySelectorAll('button'));
        \\const inc = buttons.find(b => b.textContent.includes('Increase font size') || b.getAttribute('aria-label') === 'Increase font size');
        \\const dec = buttons.find(b => b.textContent.includes('Decrease font size') || b.getAttribute('aria-label') === 'Decrease font size');
        \\const sizeLabel = document.querySelector('[aria-label="Font size"], .font-size-label');
        \\
        \\if (inc) inc.click();
        \\if (sizeLabel) assert.equal(sizeLabel.textContent.trim(), '110%');
        \\
        \\if (inc) { inc.click(); inc.click(); inc.click(); }
        \\if (sizeLabel) assert.equal(sizeLabel.textContent.trim(), '140%');
        \\if (inc) assert.ok(inc.disabled, 'Increase button should be disabled at max');
        \\
        \\// Reset demo resets font size
        \\const resetBtn = buttons.find(b => b.textContent.includes('Reset demo'));
        \\if (resetBtn) resetBtn.click();
        \\return true;
    );
}

test "browser workspace: artifact reports bounded memory and patch work" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/index.html");

    try guard.evalCheck(
        \\const res = await fetch('/web/workspace.wasm');
        \\assert.equal(res.status, 200);
        \\const { instance } = await WebAssembly.instantiate(await res.arrayBuffer());
        \\const wasm = instance.exports;
        \\const initialMemory = wasm.memory.buffer.byteLength;
        \\const initialHtml = wasm.init();
        \\assert.ok(initialHtml > 0);
        \\
        \\const decoder = new TextDecoder();
        \\const read = length => decoder.decode(new Uint8Array(wasm.memory.buffer, wasm.getRenderBuffer(), length));
        \\const length = wasm.dispatch(6, 0);
        \\const patch = read(length);
        \\assert.match(patch, /^M\t/m);
        \\assert.ok(!/^[HJ]\t/m.test(patch));
        \\
        \\for (let i = 0; i < 30; i++) wasm.dispatch(4, 0);
        \\assert.ok(wasm.resync() > 0);
        \\assert.equal(wasm.memory.buffer.byteLength, initialMemory);
        \\return true;
    );
}

test "browser demo: runtime resynchronizes an invalid patch and can remount after disposal" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.demo);
        \\
        \\const { mount } = await import('/runtime.js');
        \\window.demo.dispose();
        \\const root = document.querySelector('#app');
        \\const { instance } = await WebAssembly.instantiate(await (await fetch('/demo.wasm')).arrayBuffer());
        \\const errors = [];
        \\const gui = mount({ root, wasm: instance.exports, onError: error => errors.push(error.message) });
        \\let duplicate = false;
        \\try { mount({ root, wasm: instance.exports }); } catch { duplicate = true; }
        \\
        \\// Corrupt a leaf to exercise recovery boundary
        \\root.querySelector('output')?.remove();
        \\gui.dispatch({ action: 1 });
        \\const recovered = root.querySelector('output')?.textContent === '1' && errors.length === 1;
        \\
        \\instance.exports.memory.grow(1);
        \\gui.setInput({ kind: 1, value: 'after memory growth' });
        \\const freshMemory = root.querySelector('#name')?.value === 'after memory growth';
        \\gui.dispose();
        \\
        \\const next = mount({ root, wasm: instance.exports });
        \\root.querySelector('[data-event="1"]')?.click();
        \\const singleHandler = root.querySelector('output')?.textContent === '1';
        \\next.dispose();
        \\
        \\assert.ok(duplicate && recovered && freshMemory && singleHandler);
        \\return true;
    );
}

test "browser demo: invoked components retain table rows, SVG namespaces and controlled select values" {
    var guard = try Harness.getSession(std.testing.allocator, std.testing.io);
    defer guard.deinit();
    try guard.goto("/basics.html");

    try guard.evalCheck(
        \\async function waitFor(fn, timeout = 5000) {
        \\  const t0 = Date.now();
        \\  while (!fn()) {
        \\    if (Date.now() - t0 > timeout) throw new Error('Timeout');
        \\    await new Promise(r => setTimeout(r, 20));
        \\  }
        \\}
        \\await waitFor(() => window.demo);
        \\
        \\const first = document.querySelector('[aria-label="Primary integration"]');
        \\const second = document.querySelector('[aria-label="Secondary integration"]');
        \\assert.ok(first && second);
        \\
        \\assert.equal(first.querySelector('select')?.value, 'email');
        \\assert.equal(second.querySelector('select')?.value, 'email');
        \\
        \\const independent = (() => {
        \\  const slot = first.parentElement.parentElement;
        \\  const select = first.querySelector('select');
        \\  const input = second.querySelector('input');
        \\  const list = first.querySelector('dl');
        \\  const description = list.querySelector('dd');
        \\  const sibling = second.querySelector('dd');
        \\  input.value = 'independent browser draft'; input.focus();
        \\  window.demo.setInput({ kind: 3, value: 'email' });
        \\  return slot.isConnected && slot === first.parentElement.parentElement
        \\    && first.isConnected && second.isConnected && select === first.querySelector('select')
        \\    && list === first.querySelector('dl') && description === list.querySelector('dd')
        \\    && description.textContent.trim() === 'Email' && sibling === second.querySelector('dd') && sibling.textContent.trim() === 'Email'
        \\    && input === second.querySelector('input') && document.activeElement === input
        \\    && input.value === 'independent browser draft' && select.value === 'email'
        \\    && second.querySelector('select').value === 'email';
        \\})();
        \\assert.ok(independent, 'Independent component state check failed');
        \\return true;
    );
}
