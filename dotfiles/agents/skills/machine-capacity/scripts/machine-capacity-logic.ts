export interface Resources {
  cpus: number;
  memoryMiB: number;
}

export function reservedCpus(profile: string, cores: number): number {
  return profile === 'attended' ? (cores > 8 ? 4 : cores > 4 ? 2 : 1) : 0;
}

export function aggregateCpus(profile: string, cores: number): number {
  return cores - reservedCpus(profile, cores);
}

export function memoryFloorMiB(profile: string, memoryTotalMiB: number): number {
  return Math.max(profile === 'attended' ? memoryTotalMiB / 5 : memoryTotalMiB / 12, 8192);
}

export function resourceClass(kind: string, cores: number): Resources {
  switch (kind) {
    case 'agent': return { cpus: 0, memoryMiB: 768 };
    case 'native': return { cpus: cores > 1 ? 2 : 1, memoryMiB: 4096 };
    case 'moderate': return { cpus: cores > 1 ? 2 : 1, memoryMiB: 2048 };
    case 'heavy': return { cpus: cores > 8 ? 6 : cores > 4 ? 3 : 1, memoryMiB: 8192 };
    case 'gpu': return { cpus: 1, memoryMiB: 2048 };
    case 'critical': return { cpus: cores - reservedCpus('attended', cores), memoryMiB: 16384 };
    case 'exclusive': return { cpus: cores, memoryMiB: 16384 };
    default: throw new Error('Unknown resource class');
  }
}

export function reserveClass(kind: string): boolean {
  return kind === 'agent';
}

export function nativeMemoryRequest(kind: string, cores: number, memoryGiB: number): Resources {
  const base = resourceClass(kind, cores);
  if (kind !== 'native' || !(memoryGiB > 0)) {
    throw new Error('--memory-gib requires a positive native memory request');
  }
  return { cpus: base.cpus, memoryMiB: memoryGiB * 1024 };
}

export function batchClass(kind: string): boolean {
  return ['moderate', 'heavy', 'exclusive', 'gpu', 'critical'].includes(kind);
}

export function maximumSeconds(kind: string): number {
  return kind === 'exclusive' ? 900 : 3600;
}

export function sessionSeconds(kind: string): number {
  return kind === 'exclusive' ? 900 : batchClass(kind) ? 1800 : 0;
}

export function batchPressureLimitBasisPoints(): number {
  return 3000;
}

export function gpuBusyLimitPercent(): number {
  return 85;
}

export function gpuSlots(): number {
  return 2;
}

export function nativeGpuDecision(profile: string, gpuBusyPercent: number, gpuClients: number, gpuRuns: number): string {
  if (profile === 'attended' && gpuClients >= 4) return 'DEFER_GPU_CLIENTS';
  if (gpuBusyPercent >= gpuBusyLimitPercent() && gpuRuns === 0) return 'DEFER_GPU_BUSY';
  return 'RUN';
}

export function admissionDecision(
  profile: string,
  kind: string,
  cores: number,
  memoryTotalMiB: number,
  memoryAvailableMiB: number,
  cpuSomeAvg10BasisPoints: number,
  protectedCpuSomeAvg10BasisPoints: number,
  leasedMemoryMiB: number,
  leasedBatchCpus: number,
  leasedNativeCpus: number,
  requestedCpus: number,
  requestedMemoryMiB: number,
  peerBatchRuns: number,
  peerExclusiveRuns: number,
  unboundedRuns: number,
  queuedAhead: number,
  exclusiveWaiting: number,
  gpuBusyPercent: number,
  gpuClients: number,
  gpuRuns: number,
  nativeWaiting: number,
): string {
  if (profile !== 'attended' && profile !== 'unattended') throw new Error('Unknown capacity profile');
  if (cores <= 0 || memoryTotalMiB <= 0 || memoryAvailableMiB <= 0 || requestedCpus < 0 || requestedMemoryMiB <= 0) return 'INVALID';
  if (memoryAvailableMiB - requestedMemoryMiB < memoryFloorMiB(profile, memoryTotalMiB)) return 'DEFER_MEMORY_HEADROOM';
  if ((leasedMemoryMiB + requestedMemoryMiB) * 4 > memoryTotalMiB * 3) return 'DEFER_MEMORY_CAPACITY';
  if (kind === 'agent') return 'RUN';
  if (kind === 'native') {
    if (leasedNativeCpus + requestedCpus > aggregateCpus(profile, cores)) return 'DEFER_NATIVE_CPUS';
    return nativeGpuDecision(profile, gpuBusyPercent, gpuClients, gpuRuns);
  }
  if (unboundedRuns > 0) return 'DEFER_UNBOUNDED_PEER';
  if (peerExclusiveRuns > 0) return 'DEFER_EXCLUSIVE';
  if (kind === 'critical') {
    return profile === 'attended' && protectedCpuSomeAvg10BasisPoints >= 1000 ? 'DEFER_INTERACTIVE_PRESSURE' : 'RUN';
  }
  if (kind === 'gpu' && nativeWaiting > 0) return 'DEFER_NATIVE_WAITING';
  if (kind === 'gpu' && gpuRuns >= gpuSlots()) return 'DEFER_GPU_SLOTS';
  if (kind === 'exclusive') {
    if (exclusiveWaiting > 0) return 'DEFER_QUEUED';
    return peerBatchRuns > 0 ? 'DEFER_EXCLUSIVE' : 'RUN';
  }
  if (exclusiveWaiting > 0 && kind === 'heavy') return 'DEFER_EXCLUSIVE_QUEUED';
  if (profile === 'attended' && protectedCpuSomeAvg10BasisPoints >= 1000) return 'DEFER_INTERACTIVE_PRESSURE';
  if (queuedAhead > 0) return 'DEFER_QUEUED';
  if (leasedBatchCpus + requestedCpus > aggregateCpus(profile, cores)) return 'DEFER_CPU_CAPACITY';
  if (cpuSomeAvg10BasisPoints > batchPressureLimitBasisPoints()) return 'DEFER_CPU_PRESSURE';
  return 'RUN';
}

export function sizingHeadroom(): number {
  return 1.25;
}

export function sizedClass(gpuShare: number, cpus: number, memoryMiB: number): string {
  return gpuShare >= 0.2 ? 'gpu' : cpus <= 2 && memoryMiB <= 2048 ? 'moderate' : 'heavy';
}

export function sizedResources(cpus: number, memoryMiB: number, cores: number): Resources {
  return { cpus: Math.max(1, Math.min(cpus, resourceClass('heavy', cores).cpus)), memoryMiB: Math.max(512, memoryMiB) };
}

export function p90(values: readonly number[]): number {
  let best = -1;
  for (const value of values) {
    const below = values.reduce((count, other) => count + (other <= value ? 1 : 0), 0);
    if (below * 10 >= values.length * 9 && (best < 0 || value < best)) best = value;
  }
  return best;
}

export function learnedClass(kind: string): boolean {
  return ['moderate', 'heavy', 'native', 'gpu'].includes(kind);
}

export function learnedMinimumRuns(): number {
  return 3;
}

export function chargedResources(kind: string, cores: number, runCores: readonly number[], runMemoryMiB: readonly number[]): Resources {
  const declared = resourceClass(kind, cores);
  if (!learnedClass(kind) || runCores.length < learnedMinimumRuns() || runMemoryMiB.length < learnedMinimumRuns()) return declared;
  const cpus = p90(runCores);
  return { cpus: Math.max(1, Math.min(cpus, declared.cpus * 1.5)), memoryMiB: p90(runMemoryMiB) * 1.2 };
}
