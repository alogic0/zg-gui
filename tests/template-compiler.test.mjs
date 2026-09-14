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
  try {
    await writeFile(source, '<div>\n<span :text="$name + bad()"></span>\n</div>');
    await writeFile(generated, 'previous successful artifact');
    let result = spawnSync(compiler, [source, generated], { encoding: 'utf8' });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /view\.gui\.html:2:7: expected \$field\.path/);
    assert.equal(await readFile(generated, 'utf8'), 'previous successful artifact');
    const cases = [
      { html: '<p></p>', view: '.{}', setup: 'comptime { gui.template.validateNamespaces(&.{ .{ .first=1, .count=10 }, .{ .first=10, .count=2 } }); }\n', message: /overlapping template namespaces/ },
      { html: '<p></p>', view: '.{}', setup: 'comptime { (gui.template.Namespace{ .first=0, .count=1 }).validate(); }\n', message: /invalid template namespace range/ },
      { html: '<p :text="$missing"></p>', view: '.{}', message: /view\.gui\.html:1:4: unknown binding field 'missing'/ },
      { html: '<button :on-click="$action">Go</button>', view: '.{ .action = @as(u32, 1) }', message: /actions and input kinds must be enum values/ },
      { html: '<button disabled="$disabled">Go</button>', view: '.{ .disabled = "false" }', message: /Boolean HTML attributes require bool/ },
    ];
    for (const example of cases) {
      await writeFile(source, example.html);
      result = spawnSync(compiler, [source, generated], { encoding: 'utf8' });
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
