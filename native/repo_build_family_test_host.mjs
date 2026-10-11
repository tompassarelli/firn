// SPDX-License-Identifier: MIT OR Apache-2.0

import { lstatSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { join, relative } from 'node:path';

const build = await import(new URL('./firn/repo-build-test.js', import.meta.url));
const responsibility = await import(
  new URL('./firn/responsibility-projection-test.js', import.meta.url)
);

function errno(error) {
  return Math.abs(Number(error?.errno ?? 1));
}

function result(status, value = null) {
  return Object.freeze({ status, value });
}

const repo = process.argv[2];
const metadataRoot = new URL('.', import.meta.url).pathname;
const sources = readdirSync(join(repo, 'modules')).flatMap(name => {
  const source = join(repo, 'modules', name, 'tags.clause');
  try { return lstatSync(source).isFile() ? [source] : []; }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
});
const sourceFile = join(metadataRoot, 'metadata.clause');
const outputFile = join(metadataRoot, 'metadata.js');
const bodies = sources.map((source,index) => {
  const text = readFileSync(source, 'utf8');
  if (!text.startsWith('import "../../native/module_metadata.clause"\n') ||
      !text.includes('export metadata(): ModuleMetadata')) throw new Error(`unrecognized metadata source: ${source}`);
  return text.replace('import "../../native/module_metadata.clause"', '')
    .replace('export metadata()', `export metadata-${index}()`);
});
writeFileSync(sourceFile, `import "${relative(metadataRoot, join(repo, 'native/module_metadata.clause'))}"\n${bodies.join('\n')}`);
const compiled = Bun.spawnSync([process.env.FIRN_CLAUSE_WORKBENCH, 'compile-js', sourceFile, outputFile], {stdout:'pipe',stderr:'pipe'});
if (compiled.exitCode !== 0) throw new Error(compiled.stderr.toString());
const metadata = createRequire(import.meta.url)(outputFile);
const bySource = new Map(sources.map((source,index) => [source, metadata[`metadata-${index}`]()]));

const bridge = Object.freeze({
  readModuleMetadataSource(compiler, source) {
    const value = bySource.get(source);
    return value ? Object.freeze({status:0,value,message:''}) : Object.freeze({status:2,value:null,message:'metadata not compiled'});
  },
  metadataTags(result) { return result.value.tags; },
  metadataOptIn(result) { return result.value.optIn; },
  message(result) { return result.message; },
  env(name) { return process.env[name] ?? null; },
  status(value) { return value.status; },
  value(value) { return value.value; },
  listDirectory(path, maximum) {
    try {
      const names = readdirSync(path);
      return names.length > maximum ? result(27) : result(0, names);
    } catch (error) {
      return result(errno(error));
    }
  },
  pathKind(path) {
    try {
      const stat = lstatSync(path);
      return result(0, stat.isDirectory() ? 2 : stat.isSymbolicLink() ? 3 : 1);
    } catch (error) {
      return result(errno(error));
    }
  },
  readText(path, maximum) {
    try {
      const bytes = readFileSync(path);
      return bytes.length > maximum ? result(27) : result(0, bytes.toString('utf8'));
    } catch (error) {
      return result(errno(error));
    }
  },
});

const results = [
  build["run-scenarios"](),
  responsibility.test(bridge, [repo]),
];
process.exitCode = results.every((status) => status === 0) ? 0 : 1;
