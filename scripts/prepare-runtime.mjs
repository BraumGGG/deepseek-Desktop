import { mkdir, cp } from 'node:fs/promises';
import { join } from 'node:path';

const root = new URL('..', import.meta.url).pathname;
await mkdir(join(root, 'harness-dist'), { recursive: true });
console.log('请将固定版本 @deepseek-ai/dsh 的生产构建复制到 harness-dist/，并将 Windows Node runtime 放入 runtime/node.exe。');
