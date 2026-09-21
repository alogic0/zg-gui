import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, writeFile, readdir, unlink, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { chromium } from 'playwright';
import { serve } from '../tools/server.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));

// Exercise the real compiler and projections before applying their output in a browser.
async function projectFrames({ template, declarations, views }) {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-template-dom-'));
  try {
    const source = join(directory, 'view.gui.html');
    const generated = join(directory, 'generated.zig');
    const wrapper = join(directory, 'main.zig');
    await writeFile(source, template);
    const compiled = spawnSync(join(root, 'zig-out/bin/zg-template'), [source, generated], { encoding: 'utf8' });
    assert.equal(compiled.status, 0, compiled.stderr);
    await writeFile(wrapper, `const std = @import("std");
const gui = @import("zg_gui");
const fixture = @import("fixture");
${declarations}
pub fn main() void {
    const P = gui.Projection(fixture.snapshot_capacity);
    var previous = P.Snapshot{};
    const views: []const View = &.{ ${views} };
    for (views, 0..) |view, i| {
        var html_bytes: [4096]u8 = undefined;
        var patch_bytes: [4096]u8 = undefined;
        var html = gui.html.Writer{ .buffer = &html_bytes };
        var output = gui.html.Writer{ .buffer = &patch_bytes };
        var patches = gui.patch.Writer{ .output = &output };
        var next = P.Snapshot{};
        var p = P{ .html = &html, .next = &next,
            .previous = if (i == 0) null else &previous,
            .patches = if (i == 0) null else &patches, .writing = i == 0 };
        fixture.project(&p, view);
        if (html.failed or output.failed) @panic("projection rejected");
        std.debug.print("{s}\\x00", .{if (i == 0) html.slice() else output.slice()});
        previous = next;
    }
}
`);
    const projected = spawnSync('zig', ['run', '--dep', 'zg_gui', '--dep', 'fixture', '-Mroot=' + wrapper,
      '-Mzg_gui=' + join(root, 'src/root.zig'), '--dep', 'zg_gui', '-Mfixture=' + generated], { encoding: 'utf8' });
    assert.equal(projected.status, 0, projected.stderr);
    assert.ok(projected.stderr.endsWith('\0'));
    return projected.stderr.slice(0, -1).split('\0');
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
}

test('generated input kind changes precede controlled values in either attribute order', async () => {
  const server = await serve({ directory: join(root, 'web') });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    for (const attributes of [':value="$value" type="$kind"', 'type="$kind" :value="$value"']) {
      const frames = await projectFrames({
        template: `<section><input ${attributes}><input value="draft"></section>`,
        declarations: 'const View = struct { value: []const u8, kind: gui.template.InputType };',
        views: '.{ .value = "123", .kind = .number }, .{ .value = "abc", .kind = .text }, .{ .value = "abc", .kind = .text }, .{ .value = "456", .kind = .number }',
      });
      assert.equal(frames[2], '');
      const result = await page.evaluate(async frames => {
        const { createDomHost } = await import('/dom.js');
        const root = document.createElement('main'); document.body.append(root);
        const dom = createDomHost({ root }); dom.initialize(frames[0]);
        const parent = root.firstElementChild, input = parent.firstElementChild, sibling = parent.lastElementChild;
        input.focus();
        dom.applyPatchStream(frames[1]); dom.applyPatchStream(frames[2]);
        const text = input.type === 'text' && input.value === 'abc' && document.activeElement === input;
        sibling.focus(); sibling.setSelectionRange(1, 3);
        dom.applyPatchStream(frames[3]);
        const result = {
          text, number: input.type === 'number' && input.value === '456',
          retained: root.firstElementChild === parent && parent.firstElementChild === input
            && parent.lastElementChild === sibling && document.activeElement === sibling
            && sibling.value === 'draft' && sibling.selectionStart === 1 && sibling.selectionEnd === 3,
        };
        dom.dispose(); root.remove();
        return result;
      }, frames);
      assert.deepEqual(result, { text: true, number: true, retained: true });
    }
  } finally { await browser?.close(); await server.close(); }
});

test('generated textarea values preserve leading newlines in HTML and patches', async () => {
  const server = await serve({ directory: join(root, 'web') });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    const frames = await projectFrames({
      template: '<textarea :value="$value"></textarea>',
      declarations: 'const View = struct { value: []const u8 };',
      views: '.{ .value = "\\n\\n<&>" }, .{ .value = "\\n\\n<&>" }, .{ .value = "\\nchanged" }',
    });
    assert.equal(frames[1], '');
    const result = await page.evaluate(async frames => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root });
      dom.initialize(frames[0]); dom.applyPatchStream(frames[1]);
      const initial = root.firstElementChild.value;
      dom.applyPatchStream(frames[2]);
      const updated = root.firstElementChild.value;
      dom.initialize(frames[0]);
      const recovered = root.firstElementChild.value;
      dom.initialize('<section><input value="draft"><div data-node-id="99"></div></section>');
      const parent = root.firstElementChild, input = parent.firstElementChild, owner = parent.lastElementChild;
      input.focus(); input.setSelectionRange(1, 3);
      dom.applyPatchStream('H\t99\t' + JSON.stringify(frames[0]) + '\n');
      const replaced = owner.firstElementChild.value;
      dom.applyPatchStream('H\t99\t""\nJ\t99\t' + JSON.stringify(frames[0]) + '\n');
      const textarea = owner.firstElementChild;
      const appended = textarea.value;
      dom.applyPatchStream(frames[2]);
      return {
        initial, updated, recovered, replaced, appended,
        retained: root.firstElementChild === parent && parent.lastElementChild === owner
          && owner.firstElementChild === textarea && textarea.value === '\nchanged'
          && parent.firstElementChild === input && document.activeElement === input
          && input.value === 'draft' && input.selectionStart === 1 && input.selectionEnd === 3,
      };
    }, frames);
    assert.deepEqual(result, {
      initial: '\n\n<&>', updated: '\nchanged', recovered: '\n\n<&>',
      replaced: '\n\n<&>', appended: '\n\n<&>', retained: true,
    });
  } finally { await browser?.close(); await server.close(); }
});

test('generated option text patches restore declared selection without a value patch', async () => {
  const frames = await projectFrames({
    template: '<section><select :value="$selected"><option :text="$first"></option><option :text="$second"></option></select><select :value="$selected"><option value="a" :text="$first"></option><option value="c" :text="$second"></option></select><select><option :text="$first"></option><option :text="$second"></option></select><input value="draft"></section>',
    declarations: 'const View = struct { selected: []const u8 = "a", first: []const u8, second: []const u8 };',
    views: '.{ .first = "a", .second = "c" }, .{ .first = "b", .second = "a" }, .{ .first = "b", .second = "a" }, .{ .first = "b", .second = "c" }, .{ .first = "a", .second = "c" }',
  });
  assert.equal(frames[2], '');
  for (const frame of frames.slice(1)) {
    for (const line of frame.split('\n').filter(Boolean)) assert.ok(line.startsWith('T\t'), line);
  }
  const server = await serve({ directory: join(root, 'web') });
  let browser;
  try {
    browser = await chromium.launch({ headless: true });
    const page = await browser.newPage();
    await page.goto(server.url + '/dom.js');
    const result = await page.evaluate(async frames => {
      const { createDomHost } = await import('/dom.js');
      const root = document.createElement('main'); document.body.append(root);
      const dom = createDomHost({ root }); dom.initialize(frames[0]);
      const parent = root.firstElementChild, input = parent.lastElementChild;
      const [controlled, explicit, uncontrolled] = parent.querySelectorAll('select');
      const originalOptions = [...parent.querySelectorAll('option')];
      input.value = 'browser draft';
      controlled.focus();
      dom.applyPatchStream(frames[1]); dom.applyPatchStream(frames[2]);
      const swapped = controlled.value === 'a' && controlled.selectedIndex === 1;
      const native = explicit.value === 'a' && explicit.selectedIndex === 0
        && uncontrolled.value === 'b' && uncontrolled.selectedIndex === 0;
      dom.applyPatchStream(frames[3]);
      const absent = controlled.value === '' && controlled.selectedIndex === -1;
      dom.applyPatchStream(frames[4]);
      return {
        swapped, native, absent, restored: controlled.value === 'a' && controlled.selectedIndex === 0,
        retained: root.firstElementChild === parent && parent.firstElementChild === controlled
          && document.activeElement === controlled && parent.lastElementChild === input
          && input.value === 'browser draft'
          && [...parent.querySelectorAll('option')].every((option, i) => option === originalOptions[i]),
      };
    }, frames);
    assert.deepEqual(result, { swapped: true, native: true, absent: true, restored: true, retained: true });
  } finally { await browser?.close(); await server.close(); }
});
