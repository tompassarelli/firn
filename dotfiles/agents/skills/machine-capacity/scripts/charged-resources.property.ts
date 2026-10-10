// Property: a declared class is charged its declared size until three runs exist,
// then the nearest-rank p90 of measured cores within [1, 1.5 x declared] and p90 peak memory + 20%.
const policy = await import(Bun.argv[2]);
const { chargedResources, resourceClass } = policy;

const reference = (values: number[]) => [...values].sort((a, b) => a - b)[Math.ceil(values.length * 0.9) - 1];

let seed = Number(Bun.argv[3] ?? 0x5eed);
const random = () => {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
};
const kinds = ['moderate', 'heavy', 'native', 'gpu', 'exclusive', 'critical', 'agent'];
const learned = new Set(['moderate', 'heavy', 'native', 'gpu']);

for (let trial = 0; trial < 2000; trial += 1) {
  const kind = kinds[Math.floor(random() * kinds.length)];
  const cores = 1 + Math.floor(random() * 32);
  const runs = Math.floor(random() * 21);
  const runCores = Array.from({ length: runs }, () => Math.round(random() * 1200) / 100);
  const runMemory = Array.from({ length: runs }, () => Math.round(random() * 20000));
  const declared = resourceClass(kind, cores);
  const charged = chargedResources(kind, cores, runCores, runMemory);
  const expected = learned.has(kind) && runs >= 3
    ? { cpus: Math.min(Math.max(reference(runCores), 1), declared.cpus * 1.5), memoryMiB: reference(runMemory) * 1.2 }
    : declared;
  if (charged.cpus !== expected.cpus || Math.abs(charged.memoryMiB - expected.memoryMiB) > 1e-9) {
    console.error(JSON.stringify({ seed: Bun.argv[3] ?? 0x5eed, trial, kind, cores, runCores, runMemory, charged, expected }));
    process.exit(1);
  }
}
console.log('charged-resources property: 2000 cases PASS');
