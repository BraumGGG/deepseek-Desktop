# DeepSeek Harness 桌面版

这是开源项目 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 Windows 10/11 x64 独立桌面客户端。

## 产品功能

- 在独立桌面窗口中启动 DeepSeek Harness Web UI。
- 内置便携版 Node.js，用户无需另外安装 Node.js。
- Harness 服务仅监听本机地址 `127.0.0.1`，并自动选择可用端口。
- 生成简体中文 NSIS 安装包。
- 打包前执行真实冷启动验证，避免安装后缺少依赖或启动闪退。
- 启动失败时记录退出码、错误信息和日志路径，便于排查问题。

## 当前状态

当前版本已经完成 Windows x64 安装包构建和安装后冷启动验证。

需要注意：DeepSeek Harness 官方仍处于开发者预览阶段，上游版本可能出现不兼容变更。本项目会固定经过验证的 Harness 版本，再生成桌面安装包。

## 开发环境

要求：

- Windows 10/11 x64
- Node.js 22 或更高版本
- 与项目锁定的 Tauri 依赖兼容的 Rust 工具链
- pnpm 11 或更高版本

安装桌面端依赖并启动开发模式：

```powershell
npm install
npm run dev
```

## 发布构建

发布流程不会把生成的运行时、依赖缓存或安装包提交到 Git 仓库：

```powershell
pnpm install
pnpm run build:official
pnpm --filter @deepseek-ai/dsh deploy --prod --legacy
npm run release:runtime
npm run verify:runtime
npm run release:resources
npx tauri build --bundles nsis
```

运行时 staging 步骤会完成以下工作：

1. 计算 Harness 的生产依赖闭包。
2. 将 workspace 依赖实体化，移除 pnpm 链接和循环目录。
3. 排除测试文件、类型声明、开发文档和构建缓存。
4. 使用内置 Node.js 启动 Harness 并检查本地端口。
5. 验证通过后，才同步到 Tauri resources 并生成 NSIS 安装包。

如果运行时缺少依赖、Node 提前退出或服务无法监听端口，构建流程会直接失败，不会生成未经验证的安装包。

## 日志位置

启动日志写入当前用户的应用数据目录：

```text
%APPDATA%\ai.deepseek.harness.desktop\logs\harness.log
```

具体路径以 Windows 当前用户环境为准。如果启动失败，请优先查看该日志文件。

## 项目结构

```text
DeepSeek Harness Desktop/
├─ src-tauri/                 Tauri 桌面壳和 Rust 启动器
├─ ui/                        启动页面和前端健康检查
├─ scripts/                   运行时构建、验证和发布脚本
├─ docs/                      设计说明和实施计划
├─ progress.md                项目进度记录
└─ findings.md                构建和运行问题记录
```

生成的 `runtime/`、`release-staging/`、`src-tauri/resources/`、Rust `target/` 和安装包不会提交到 Git 仓库。

## 开源许可

DeepSeek Harness 是独立的开源项目，其源码、许可证、第三方声明和版本更新由上游项目维护。本仓库主要包含 Windows 桌面封装、启动器和发布工具。

请同时遵守本项目和 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的许可证及第三方依赖声明。
