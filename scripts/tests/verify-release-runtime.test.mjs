import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { verifyRuntime } from '../verify-release-runtime.mjs';

async function fixture(source) {
  const root = await mkdtemp(join(tmpdir(), 'dsh-runtime-test-'));
  await mkdir(join(root, 'lib'));
  await writeFile(join(root, 'lib', 'bin.js'), source);
  return root;
}

test('缺少入口时立即报告明确错误', async () => {
  const root = await mkdtemp(join(tmpdir(), 'dsh-runtime-test-'));
  await assert.rejects(
    verifyRuntime({ nodePath: process.execPath, runtimePath: root, timeoutMs: 1000 }),
    /Harness 入口不存在/,
  );
});

test('子进程提前退出时返回 stderr 和退出码', async () => {
  const root = await fixture("process.stderr.write('fixture missing dependency'); process.exit(7);\n");
  await assert.rejects(
    verifyRuntime({ nodePath: process.execPath, runtimePath: root, timeoutMs: 3000 }),
    /退出码 7[\s\S]*fixture missing dependency/,
  );
});

test('HTTP 服务监听后返回运行时指标', async () => {
  const root = await fixture(`
    import http from 'node:http';
    const index = process.argv.indexOf('--port');
    const port = Number(process.argv[index + 1]);
    http.createServer((request, response) => {
      response.writeHead(200, { 'content-type': 'text/plain' });
      response.end('ok');
    }).listen(port, '127.0.0.1');
  `);
  const result = await verifyRuntime({ nodePath: process.execPath, runtimePath: root, timeoutMs: 3000 });
  assert.match(result.url, /^http:\/\/127\.0\.0\.1:\d+$/);
  assert.equal(result.fileCount, 1);
  assert.ok(result.bytes > 0);
  assert.ok(result.startupMs < 3000);
});
