import { cp, lstat, mkdir, readFile, readdir, rm } from 'node:fs/promises';
import { basename, dirname, extname, join, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const config = JSON.parse(await readFile(join(projectRoot, 'scripts', 'release-runtime.config.json'), 'utf8'));
const baseRuntime = resolve(projectRoot, config.baseRuntime);
const knownGoodRuntime = resolve(projectRoot, config.knownGoodRuntime);
const output = resolve(projectRoot, config.output);
const sourceModules = join(knownGoodRuntime, 'node_modules');
const outputModules = join(output, 'node_modules');
const upstreamSource = resolve(projectRoot, 'upstream-source');
const excludedNames = new Set(config.excludeNames);
const excludedExtensions = new Set(config.excludeExtensions);

function packagePath(root, name) {
  return join(root, ...name.split('/'));
}

function shouldCopy(source) {
  const name = basename(source);
  if (excludedNames.has(name)) return false;
  if (/^readme(?:\.[^.]+)?$/i.test(name)) return false;
  if (/\.d\.(?:ts|mts|cts)$/i.test(name)) return false;
  if (excludedExtensions.has(extname(name))) return false;
  return true;
}

async function copyTree(source, destination) {
  await cp(source, destination, {
    recursive: true,
    dereference: true,
    filter: (current) => shouldCopy(current),
  });
}

async function readManifest(packageDir) {
  return JSON.parse(await readFile(join(packageDir, 'package.json'), 'utf8'));
}

async function indexWorkspacePackages(root) {
  const packages = new Map();
  const queue = [root];
  while (queue.length > 0) {
    const dir = queue.pop();
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name === 'node_modules' || entry.name === '.git') continue;
      const path = join(dir, entry.name);
      const manifest = await readManifest(path).catch(() => null);
      if (manifest?.name?.startsWith('@deepseek-ai/')) packages.set(manifest.name, path);
      queue.push(path);
    }
  }
  return packages;
}

function runtimeDependencies(manifest) {
  return [
    ...Object.keys(manifest.dependencies || {}).map((name) => ({ name, optional: false })),
    ...Object.keys(manifest.peerDependencies || {})
      .filter((name) => !manifest.peerDependenciesMeta?.[name]?.optional)
      .map((name) => ({ name, optional: false })),
    ...Object.keys(manifest.optionalDependencies || {}).map((name) => ({ name, optional: true })),
  ];
}

async function buildClosure(rootManifest, workspacePackages) {
  const queue = [...runtimeDependencies(rootManifest)];
  const copied = new Set();
  while (queue.length > 0) {
    const { name, optional } = queue.shift();
    if (copied.has(name)) continue;
    let source = packagePath(sourceModules, name);
    const installed = await lstat(source).then(() => true).catch(() => false);
    if (!installed && workspacePackages.has(name)) source = workspacePackages.get(name);
    const available = await lstat(source).then(() => true).catch(() => false);
    if (!available && optional) continue;
    if (!available) throw new Error(`已知可运行目录中缺少依赖: ${name}`);
    const manifest = await readManifest(source);
    const destination = packagePath(outputModules, name);
    await mkdir(dirname(destination), { recursive: true });
    await copyTree(source, destination);
    copied.add(name);
    for (const dependency of runtimeDependencies(manifest)) {
      if (!copied.has(dependency.name)) queue.push(dependency);
    }
  }
  return copied;
}

async function inspectTree(root) {
  let files = 0;
  let bytes = 0;
  const queue = [root];
  while (queue.length > 0) {
    const dir = queue.pop();
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      const info = await lstat(path);
      if (info.isSymbolicLink()) throw new Error(`发布目录中仍存在链接: ${path}`);
      if (entry.isDirectory()) queue.push(path);
      if (entry.isFile()) {
        files += 1;
        bytes += info.size;
      }
    }
  }
  return { files, bytes };
}

if (!output.startsWith(`${projectRoot}${sep}`)) {
  throw new Error(`拒绝写入项目路径外: ${output}`);
}
await rm(output, { recursive: true, force: true });
await mkdir(output, { recursive: true });
for (const entry of await readdir(baseRuntime, { withFileTypes: true })) {
  if (entry.name === 'node_modules') continue;
  await copyTree(join(baseRuntime, entry.name), join(output, entry.name));
}
await mkdir(outputModules, { recursive: true });
const rootManifest = await readManifest(baseRuntime);
const workspacePackages = await indexWorkspacePackages(upstreamSource);
const packages = await buildClosure(rootManifest, workspacePackages);
const metrics = await inspectTree(output);
if (metrics.files > config.maxFiles) {
  throw new Error(`精简运行时仍有 ${metrics.files} 个文件，超过阈值 ${config.maxFiles}`);
}
process.stdout.write(`${JSON.stringify({ packages: packages.size, ...metrics, output }, null, 2)}\n`);
