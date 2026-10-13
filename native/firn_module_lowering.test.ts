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
      writeFileSync(join(root, path), source.replace('option count: Int', 'option count: Int\noption count: Int'));
      const duplicate = run('build');
      expect(duplicate.exitCode).not.toBe(0);
      expect(duplicate.stderr.toString()).toContain(`${path}:6:1:`);
      expect(duplicate.stderr.toString()).toContain(`already declared at ${path}:5`);
    }
    const proofSource = `use firn/tags
type Node
given Node is seeded
derived Node holds
Seed is a Node
Gate is a Node
Goal is a Node
Seed is seeded
rule seeded: ?n holds
  when ?n is seeded
rule bypass: Goal holds
  when Seed holds
requirements
  Goal holds requires Gate holds
enable: "sample"
config
  message: "sample"
`;
    const git = (...args: string[]) => {
      const result = Bun.spawnSync(['git', ...args], { cwd: root });
      expect(result.exitCode, result.stderr.toString()).toBe(0);
    };
    git('init', '-q');
    writeFileSync(join(root, path), proofSource.replace('Seed is seeded\n', ''));
    git('add', 'config/galileo-revision', 'flake.gal', path);
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'Proof baseline');
    writeFileSync(join(root, path), proofSource);
    for (const result of [run('check'), run('review', '--base', 'HEAD')]) {
      expect(result.exitCode, result.stderr.toString()).toBe(1);
      const output = result.stdout.toString();
      expect(output).toContain('Goal holds requires Gate holds');
      expect(output).toContain('modules/sample/default/bypass (modules/sample/default:11)');
      expect(output).toContain('modules/sample/default/seeded (modules/sample/default:9)');
      expect(output).toContain('Seed is seeded    modules/sample/default:8');
    }
    const why = run('why', 'Goal', 'holds');
    expect(why.exitCode, why.stderr.toString()).toBe(0);
    expect(why.stdout.toString()).toContain('modules/sample/default/bypass (modules/sample/default.gal:11)');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
