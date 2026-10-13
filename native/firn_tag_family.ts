import * as commands from './tag_commands_family.ts';
import * as resolve from './tag_resolve_family.ts';

function resolveRequest(args: string[]): boolean {
  return ((args.length >= 2) && (args[0] === "tag") && (args[1] === "resolve"));
}

export function run(bridge: any, args: string[]): number {
  if (resolveRequest(args)) {
    return resolve.run(bridge, args);
  }
  return commands.run(bridge, args);
}
