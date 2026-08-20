import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { readdir, stat } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

async function getFreePort() {
  return new Promise((resolvePort, reject) => {
    const server = createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() => resolvePort(address.port));
    });
  });
}

async function measure(dir) {
  let fileCount = 0;
  let bytes = 0;
  const entries = await readdir(dir, { withFileTypes: true });
  for (const entry of entries) {
    const path = resolve(dir, entry.name);
    if (entry.isDirectory()) {
      const child = await measure(path);
      fileCount += child.fileCount;
      bytes += child.bytes;
    } else if (entry.isFile()) {
      fileCount += 1;
      bytes += (await stat(path)).size;
    }
  }
  return { fileCount, bytes };
}

async function stop(child) {
  if (child.exitCode !== null) return;
  child.kill('SIGTERM');
  await Promise.race([
    new Promise((resolveExit) => child.once('exit', resolveExit)),
    new Promise((resolveWait) => setTimeout(resolveWait, 2000)),
  ]);
  if (child.exitCode === null) child.kill('SIGKILL');
}

export async function verifyRuntime({ nodePath, runtimePath, timeoutMs = 120000 }) {
  const startedAt = Date.now();
  const absoluteRuntime = resolve(runtimePath);
  const absoluteNode = resolve(nodePath);
  const entry = resolve(absoluteRuntime, 'lib', 'bin.js');
  await stat(absoluteNode).catch(() => {
    throw new Error(`Node runtime 不存在: ${absoluteNode}`);
  });
  await stat(entry).catch(() => {
    throw new Error(`Harness 入口不存在: ${entry}`);
  });

  const port = await getFreePort();
  const url = `http://127.0.0.1:${port}`;
  const child = spawn(absoluteNode, [entry, 'web', '--no-open', '--port', String(port)], {
    cwd: absoluteRuntime,
    windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  child.stderr.on('data', (chunk) => { stderr += chunk; });

  try {
    while (Date.now() - startedAt < timeoutMs) {
      if (child.exitCode !== null) {
        throw new Error(`Harness 提前退出，退出码 ${child.exitCode}\n${stderr || stdout}`.trim());
      }
      try {
        const response = await fetch(url, { signal: AbortSignal.timeout(1000) });
        if (response.ok || response.status < 500) {
          const size = await measure(absoluteRuntime);
          return { url, pid: child.pid, ...size, startupMs: Date.now() - startedAt };
        }
      } catch {}
      await new Promise((resolveWait) => setTimeout(resolveWait, 200));
    }
    throw new Error(`Harness 启动超时（${timeoutMs}ms）\n${stderr || stdout}`.trim());
  } finally {
    await stop(child);
  }
}

function parseArgs(argv) {
  const values = {};
  for (let index = 0; index < argv.length; index += 2) {
    values[argv[index]] = argv[index + 1];
  }
  return values;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = parseArgs(process.argv.slice(2));
  verifyRuntime({
    nodePath: args['--node'],
    runtimePath: args['--runtime'],
    timeoutMs: Number(args['--timeout'] || 120000),
  }).then((result) => {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  }).catch((error) => {
    process.stderr.write(`${error.stack || error}\n`);
    process.exitCode = 1;
  });
}
