import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, writeFile, readdir, unlink, rmdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

test('an independent Zig package compiles and imports its own HTML template', async () => {
  const root = fileURLToPath(new URL('..', import.meta.url));
  const directory = await mkdtemp(join(tmpdir(), 'zg-gui-template-package-'));
  try {
    await writeFile(join(directory, 'build.zig.zon'),
      '.{ .name = .gui_consumer, .version = "0.0.0", .fingerprint = 0x3d0af40a357f117c,\n' +
      '.dependencies = .{ .zg_gui = .{ .path = ' + JSON.stringify(relative(directory, root)) + ' } },\n' +
      '.paths = .{ "build.zig", "build.zig.zon", "main.zig", "view.gui.html" } }\n');
    await writeFile(join(directory, 'view.gui.html'), '<output :text="$count"></output>');
    await writeFile(join(directory, 'build.zig'), [
      'const std = @import("std");',
      'pub fn build(b: *std.Build) void {',
      'const target = b.standardTargetOptions(.{});',
      'const dep = b.dependency("zg_gui", .{ .target = target, .optimize = std.builtin.OptimizeMode.debug });',
      'const gui = dep.module("zg_gui");',
      'const tests = b.addTest(.{ .root_module = b.createModule(.{',
      '.root_source_file = b.path("main.zig"), .target = target,',
      '.imports = &.{.{ .name = "zg_gui", .module = gui }} }) });',
      '@import("zg_gui").addTemplate(b, .{ .dependency = dep, .owner = tests.root_module, .name = "view", .source = b.path("view.gui.html") });',
      'b.getInstallStep().dependOn(&b.addRunArtifact(tests).step);',
      '}',
    ].join('\n'));
    await writeFile(join(directory, 'main.zig'), [
      'const std = @import("std");',
      'const gui = @import("zg_gui");',
      'const template = @import("view");',
      'test "external generated template" {',
      'var bytes: [256]u8 = undefined;',
      'var html = gui.html.Writer{ .buffer = &bytes };',
      'const P = gui.Projection(template.snapshot_capacity);',
      'var snapshot = P.Snapshot{};',
      'var p = P{ .html = &html, .next = &snapshot };',
      'template.project(&p, .{ .count = @as(u32, 42) });',
      'try std.testing.expect(!html.failed);',
      'try std.testing.expect(std.mem.indexOf(u8, html.slice(), ">42</output>") != null);',
      '}',
    ].join('\n'));
    const result = spawnSync('zig', ['build', '--cache-dir', join(root, '.zig-cache/template-package')], {
      cwd: directory, encoding: 'utf8',
    });
    assert.equal(result.status, 0, result.stdout + result.stderr);
  } finally {
    for (const file of await readdir(directory)) await unlink(join(directory, file));
    await rmdir(directory);
  }
});
