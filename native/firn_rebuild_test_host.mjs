// SPDX-License-Identifier: MIT OR Apache-2.0

const rebuild = await import(process.env.FIRN_REBUILD_TEST_MODULE);
process.exitCode = rebuild.runProperties(process.env.CI ? 64 : 16);

const core = await import(new URL('./rebuild.ts', `file://${process.env.FIRN_REBUILD_TEST_MODULE}`));
const listing = await Bun.file(new URL('./fixtures/nixos-rebuild-26.05-2026-10-11-generations.txt', import.meta.url)).text();
const rows = listing.trim().split('\n').slice(1).map(line => line.trim().split(/\s+/));
const current = rows.find(row => row.at(-1) === 'True')[0];
if (core.currentGeneration(listing) !== current || rows.some(row => !core.generationPresent(listing,row[0]))) process.exitCode=1;

const calls = [];
const reply = argv => {
  const line = argv.join(' ');
  if (line.endsWith('rev-parse HEAD')) return 'abc\n';
  if (line.endsWith('branch --show-current')) return 'main\n';
  if (line === 'uname -s') return 'Linux\n';
  if (argv[0] === 'nix' && argv[1] === 'build') return '/nix/store/system\n';
  if (line === 'nixos-rebuild list-generations') return '42 current True\n';
  return '';
};
Object.assign(globalThis, {
  firn_host_env: name => ({ FIRN_REPO: '/repo', FIRN_SNAPSHOT_DIR: '/snapshot' })[name] ?? null,
  firn_host_pid: () => 1,
  firn_host_out: () => {},
  firn_host_err: () => {},
  firn_host_git_checkout: () => false,
  firn_host_append: () => ['ok'],
  firn_host_capture: argv => { calls.push(argv.join(' ')); return ['ok', 0, reply(argv), '']; },
  firn_host_inherit: argv => { calls.push(argv.join(' ')); return argv.at(-1) === 'switch' ? 4 : 0; },
});
const native = await import(new URL('./rebuild_native.ts', `file://${process.env.FIRN_REBUILD_TEST_MODULE}`));
if (native.runCommand(['host', 'rebuild', 'box']) !== 4 || !calls.includes('git -C /repo tag -f gen-42 abc')) process.exitCode = 1;
