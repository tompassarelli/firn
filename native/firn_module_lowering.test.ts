import { expect, test } from 'bun:test';
import { chmodSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { join } from 'node:path';

const compiler = process.env.FIRN_TEST_GALILEO ?? join(homedir(), '.local/lib/firn/cli/current/bin/galileo-core');

test('module loader reports authoritative compact and literal Unicode source locations', () => {
  const root = mkdtempSync(join(tmpdir(), 'firn-source-locations-'));
  try {
    mkdirSync(join(root, 'config'));
    mkdirSync(join(root, 'modules/sample'), { recursive: true });
    writeFileSync(join(root, 'config/galileo-revision'), 'fixture');
    writeFileSync(join(root, 'flake.gal'), '');
    const lowerer = join(root, 'lower');
    writeFileSync(lowerer, `#!/usr/bin/env bash\nexec '${process.execPath}' '${join(import.meta.dir, 'firn_module_lowering.ts')}'\n`);
    chmodSync(lowerer, 0o700);
    const path = 'modules/sample/default.gal';
    const name = 'myConfig.modules.sample.enable';
    const run = (...args: string[]) => Bun.spawnSync([compiler, ...args, path], {
      cwd: root, env: { ...process.env, FIRN_MODULE_LOWERING: lowerer },
    });
    for (const enable of ['enable: "中"', '"enable": "中"', '']) {
      const source = `# compact fixture\ntags: agents\n${enable}\noption message: Text\noption count: Int\nconfig\n  message: "中" ++ (if config.${name} then "a" else "b")\n  count: 1\n`;
      writeFileSync(join(root, path), source);
      const build = run('build');
      expect(build.exitCode, build.stderr.toString()).toBe(0);
      const built = readFileSync(join(root, path.replace('.gal', '.nix')), 'utf8');
      expect(built).toContain('lib.mkIf config.myConfig.modules.sample.enable');
      const refs = run('refs', name);
      expect(refs.exitCode, refs.stderr.toString()).toBe(0);
      const output = refs.stdout.toString();
      expect(output).toContain(`${path}:${enable ? 3 : 6}: implied option ${name}`);
      expect(output).toContain(`${path}:6:1: implied config.${name}`);
      const line = source.split('\n')[6];
      const column = [...line.slice(0, line.indexOf(`config.${name}`))].length + 1;
      expect(output).toContain(`${path}:7:${column}: config.${name}`);
      const broken = source.replace('count: 1', `count: "中" ++ length(config.${name})`);
      writeFileSync(join(root, path), broken);
      const diagnostic = run('build');
      expect(diagnostic.exitCode).not.toBe(0);
      const stderr = diagnostic.stderr.toString();
      const errorLine = broken.split('\n')[7];
      const errorColumn = [...errorLine.slice(0, errorLine.indexOf('length'))].length + 1;
      expect(stderr).toContain(`${path}:8:${errorColumn}:`);
      expect(stderr).toContain('    ' + broken.split('\n')[7]);
      expect(stderr).not.toContain('    ' + '  ' + broken.split('\n')[7]);
    }
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
