# Windows 发布清单

当前已验证的安装包：

- 文件：src-tauri/target/release/bundle/nsis/DeepSeek Harness_0.1.0_x64-setup.exe
- 平台：Windows 10/11 x64
- SHA256：796263C7840E9E1AE69BB91D7C703D89668EF151A8A066BDEF440A2C8C2D913F
- 实际静默安装：25.44 秒
- 安装后运行时冷启动：3.701 秒
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
