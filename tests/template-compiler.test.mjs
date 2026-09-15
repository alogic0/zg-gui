import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFile, writeFile, mkdtemp, readdir, unlink, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const compiler = join(root, 'zig-out/bin/zg-template');

test('vendored source hashes remain pinned', async () => {
  const { createHash } = await import('node:crypto');
  const directory = join(root, 'vendor/superhtml');
  const manifest = JSON.parse(await readFile(join(directory, 'provenance.json'), 'utf8'));
  for (const [file, hash] of Object.entries(manifest.files))
    assert.equal(createHash('sha256').update(await readFile(join(directory, file))).digest('hex'), hash, file);
});

test('template diagnostics preserve output and typed bindings fail at compile time', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-template-'));
  const source = join(directory, 'view.gui.html');
  const generated = join(directory, 'generated.zig');
  const wrapper = join(directory, 'consumer.zig');
  const component = join(directory, 'field.gui.html');
  try {
    await writeFile(source, '<div>\n<span :text="$name + bad()"></span>\n</div>');
    await writeFile(generated, 'previous successful artifact');
    let result = spawnSync(compiler, [source, generated], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /view\.gui\.html:2:7: expected \$field\.path/);
    assert.equal(await readFile(generated, 'utf8'), 'previous successful artifact');
    const invocation = '<template :component="field" :view="$field" :ref="field"></template>';
    const cases = [
      { html: '<div :style-vars="$layout"></div>', view: '.{ .layout = .{} }', message: /style variables require 1 to 16 fields/ },
      { html: '<div :style-vars="$layout"></div>', view: '.{ .layout = .{ .@"--gap" = "1px" } }', message: /style variable values must be integers/ },
      { html: '<div :style-vars="$layout"></div>', view: '.{ .layout = .{ .@"--bad;name" = @as(u32, 1) } }', message: /invalid style variable name/ },
      { html: '<div :style-vars="$layout"></div>', view: '.{ .layout = .{ .gap = @as(u32, 1) } }', message: /style variable names must match/ },
      { html: invocation, component: '<span></span>', view: '.{}', message: /unknown binding field 'field'/ },
      { html: invocation, component: '<span></span>', view: '.{ .field = @as(u32, 1) }', message: /component input requires a struct/ },
      { html: invocation, component: '<span :text="$missing"></span>', view: '.{ .field = .{} }', message: /field\.gui\.html:1:7: unknown binding field 'missing'/ },
      { html: invocation, component: '<button :on-click="$action">Go</button>', view: '.{ .field = .{ .action = @as(u32, 1) } }', message: /actions and input kinds must be enum values/ },
      { html: '<p></p>', view: '.{}', setup: 'comptime { gui.template.validateNamespaces(&.{ .{ .first=1, .count=10 }, .{ .first=10, .count=2 } }); }\n', message: /overlapping template namespaces/ },
      { html: '<p></p>', view: '.{}', setup: 'comptime { (gui.template.Namespace{ .first=0, .count=1 }).validate(); }\n', message: /invalid template namespace range/ },
      { html: '<p :text="$missing"></p>', view: '.{}', message: /view\.gui\.html:1:4: unknown binding field 'missing'/ },
      { html: '<button :on-click="$action">Go</button>', view: '.{ .action = @as(u32, 1) }', message: /actions and input kinds must be enum values/ },
      { html: '<button disabled="$disabled">Go</button>', view: '.{ .disabled = "false" }', message: /Boolean HTML attributes require bool/ },
    ];
    for (const example of cases) {
      await writeFile(source, example.html);
      if (example.component) await writeFile(component, example.component);
      result = spawnSync(compiler, [source, generated, ...(example.component ? ['field', component] : [])], { encoding: 'utf8' });
      assert.equal(result.status, 0, result.stderr);
      await writeFile(wrapper,
        'const gui = @import("zg_gui");\nconst fixture = @import("fixture");\n' + (example.setup || '') +
        'test "typecheck the generated application" {\n' +
        'var bytes: [1024]u8 = undefined;\nvar html = gui.html.Writer{ .buffer = &bytes };\n' +
        'const P = gui.Projection(fixture.snapshot_capacity);\nvar next = P.Snapshot{};\n' +
        'var p = P{ .html = &html, .next = &next };\nfixture.project(&p, ' + example.view + ');\n}\n');
      result = spawnSync('zig', ['test', '--dep', 'zg_gui', '--dep', 'fixture', '-Mroot=' + wrapper,
        '-Mzg_gui=' + join(root, 'src/root.zig'), '--dep', 'zg_gui', '-Mfixture=' + generated,
        '--cache-dir', resolve(root, '.zig-cache/template-negative')], { encoding: 'utf8' });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, example.message);
    }
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});


test('list fragment CLI context is explicit and rejection preserves output', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-list-'));
  const source = join(directory, 'row.gui.html'), generated = join(directory, 'row.zig');
  try {
    await writeFile(source, '<li :text="$label"></li>');
    for (const context of ['ul', 'ol']) {
      const result = spawnSync(compiler, [source, generated, `--context=${context}`], {encoding:'utf8'});
      assert.equal(result.status, 0, result.stderr);
    }
    const accepted = await readFile(generated, 'utf8');
    for (const args of [[], ['--context=div'], ['--context=ul', '--context=ol']]) {
      assert.notEqual(spawnSync(compiler, [source, generated, ...args]).status, 0);
      assert.equal(await readFile(generated, 'utf8'), accepted);
    }
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});

test('table row contexts preserve output after invalid structure or context', async () => {
  const directory=await mkdtemp(join(tmpdir(),'zg-gui-table-'));
  const source=join(directory,'row.gui.html'),generated=join(directory,'row.zig');
  try {
    await writeFile(source,'<tr><td :text="$label"></td></tr>');
    for(const context of ['thead','tbody','tfoot']) {
      const result=spawnSync(compiler,[source,generated,`--context=${context}`],{encoding:'utf8'});
      assert.equal(result.status,0,result.stderr);
    }
    const accepted=await readFile(generated,'utf8');
    for(const args of [[],['--context=ul'],['--context=table'],['--context=tbody','--context=tfoot']]) {
      assert.notEqual(spawnSync(compiler,[source,generated,...args]).status,0);
      assert.equal(await readFile(generated,'utf8'),accepted);
    }
    await writeFile(source,'text<tr><td>value</td></tr>');
    assert.notEqual(spawnSync(compiler,[source,generated,'--context=tbody']).status,0);
    assert.equal(await readFile(generated,'utf8'),accepted);
  } finally {for(const file of await readdir(directory))await unlink(join(directory,file));await rmdir(directory);}
});

test('navigation slot rejection preserves successful generated output', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-navigation-'));
  const source = join(directory, 'navigation.gui.html'), generated = join(directory, 'navigation.zig');
  try {
    await writeFile(source, '<nav aria-label="Sections" :slot="$children"></nav>');
    const result = spawnSync(compiler, [source, generated], {encoding:'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const accepted = await readFile(generated, 'utf8');
    for (const html of ['<nav :slot="$children">text</nav>', '<nav :slot="$children"><button>Go</button></nav>', '<nav :slot="$children" :text="$label"></nav>', '<nav :slot="$children" :if="$visible"></nav>']) {
      await writeFile(source, html);
      assert.notEqual(spawnSync(compiler, [source, generated]).status, 0);
      assert.equal(await readFile(generated, 'utf8'), accepted);
    }
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});

test('aside slot rejection preserves successful generated output', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-aside-'));
  const source = join(directory, 'aside.gui.html'), generated = join(directory, 'aside.zig');
  try {
    await writeFile(source, '<aside aria-label="Sections" :slot="$children"></aside>');
    const result = spawnSync(compiler, [source, generated], {encoding:'utf8'});
    assert.equal(result.status, 0, result.stderr);
    const accepted = await readFile(generated, 'utf8');
    for (const html of ['<aside :slot="$children">text</aside>', '<aside :slot="$children"><button>Go</button></aside>', '<aside :slot="$children" :text="$label"></aside>', '<aside :slot="$children" :if="$visible"></aside>']) {
      await writeFile(source, html);
      assert.notEqual(spawnSync(compiler, [source, generated]).status, 0);
      assert.equal(await readFile(generated, 'utf8'), accepted);
    }
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});

test('cell context rejects invalid roots without replacing generated output', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-cells-'));
  const source = join(directory, 'cells.gui.html'), generated = join(directory, 'cells.zig');
  try {
    await writeFile(source, '<th :text="$label"></th><td><input :value="$draft"></td>');
    const result = spawnSync(compiler, [source, generated, '--context=tr'], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const accepted = await readFile(generated, 'utf8');
    for (const html of ['<tr><td>Nested</td></tr>', 'bare<td>Value</td>', '<div>Invalid</div>']) {
      await writeFile(source, html);
      assert.notEqual(spawnSync(compiler, [source, generated, '--context=tr']).status, 0);
      assert.equal(await readFile(generated, 'utf8'), accepted);
    }
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});

test('dynamic progress rejection preserves accepted compiler output', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-progress-'));
  const source = join(directory, 'progress.gui.html'), generated = join(directory, 'progress.zig');
  try {
    await writeFile(source, '<progress max="$maximum" value="$level"></progress>');
    assert.equal(spawnSync(compiler, [source, generated]).status, 0);
    const accepted = await readFile(generated, 'utf8');
    for (const html of ['<progress max="$maximum"></progress>', '<progress max="$maximum" value="-1"></progress>', '<progress max="$maximum" value="NaN"></progress>']) {
      await writeFile(source, html);
      assert.notEqual(spawnSync(compiler, [source, generated]).status, 0);
      assert.equal(await readFile(generated, 'utf8'), accepted);
    }
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});
