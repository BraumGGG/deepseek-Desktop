# Windows 发布清单

当前已验证的安装包：

- 文件：src-tauri/target/release/bundle/nsis/DeepSeek Harness_0.1.0_x64-setup.exe
- 平台：Windows 10/11 x64
- SHA256：1A8D76B81F93D5F11A419D338D798718D6676971AC83F9BF0C9EBCF21519DBE9
- 实际静默安装：26.44 秒
- 安装后运行时冷启动：2.883 秒
- 安装后文件数：12,026

旧版哈希 DBB18EB4E1411A1DED0950402D2F00D43AB701038EA6A0F6529AD953AABC21EC 以及更早的安装包均已废弃，不应继续分发。

## 从源码重建

pnpm install
pnpm run build:official
pnpm --filter @deepseek-ai/dsh deploy --prod --legacy
npm run release:runtime
npm run verify:runtime
npm run release:resources
npx tauri build --bundles nsis

构建完成后，必须重新计算安装包 SHA256，并执行项目内隔离目录的静默安装测试：

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-installed-release.ps1

发布前还应确认 %APPDATA%\\ai.deepseek.harness.desktop\\logs\\harness.log 没有 ERR_MODULE_NOT_FOUND、panic 或提前退出信息。

## 当前更新方式

当前版本不启用自动下载更新，也不需要代码签名证书。用户从托盘选择“检查更新”，打开 GitHub Releases 最新页面，下载新安装包后直接覆盖安装即可。NSIS 安装钩子会停止旧桌面进程和 Harness 子进程，再完成替换。
