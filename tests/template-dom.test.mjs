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
