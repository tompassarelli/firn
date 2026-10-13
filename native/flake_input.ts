export type FlakeInput = { name: string; sourceModule: string; url: string };
export function makeFlakeInput(name: string, sourceModule: string, url: string): FlakeInput { return { name, sourceModule, url }; }

function inputIndex(inputs: FlakeInput[], name: string): number {
  let index: number = 0;
  while (true) {
    if ((index >= inputs.length)) {
      return -1;
    }
    if ((name === inputs[index].name)) {
      return index;
    }
    index = (index + 1);
    continue;
  }
}

export function collect(declared: FlakeInput[]): FlakeInput[] {
  let index: number = 0;
  let collected: FlakeInput[] = [];
  while (true) {
    if ((index >= declared.length)) {
      return collected;
    }
    const candidate: FlakeInput = declared[index];
    [index, collected] = [(index + 1), ((inputIndex(collected, candidate.name) < 0) ? [...collected, candidate] : collected)];
    continue;
  }
}

export function sortedInputNames(inputs: FlakeInput[]): string[] {
  let index: number = 0;
  let names: string[] = [];
  while (true) {
    if ((index >= inputs.length)) {
      return names.slice().sort();
    }
    [index, names] = [(index + 1), [...names, inputs[index].name]];
    continue;
  }
}

export function findInput(inputs: FlakeInput[], name: string): FlakeInput {
  return inputs[inputIndex(inputs, name)];
}

function member(values: string[], wanted: string): boolean {
  let index: number = 0;
  while (true) {
    if ((index >= values.length)) {
      return false;
    }else if ((values[index] === wanted)) {
      return true;
    }else {
      index = (index + 1);
      continue;
    }
  }
}

export function sourceModuleCount(inputs: FlakeInput[]): number {
  let index: number = 0;
  let modules: string[] = [];
  while (true) {
    if ((index >= inputs.length)) {
      return modules.length;
    }
    const module: string = inputs[index].sourceModule;
    [index, modules] = [(index + 1), (member(modules, module) ? modules : [...modules, module])];
    continue;
  }
}
