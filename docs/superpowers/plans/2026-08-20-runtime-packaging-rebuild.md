# Runtime Packaging Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 生成安装快速、安装后可稳定启动且经过自动冷启动验收的 DeepSeek Harness Windows x64 安装包。

**Architecture:** 从固定 Harness 构建产物生成独立、实体化的生产运行时 staging；先用内置 Node 完成启动验收，再同步到 Tauri resources 并打包 NSIS。构建和安装后的每一层都运行同一套健康检查，失败时禁止发布。

**Tech Stack:** Node.js 22、pnpm、PowerShell、Rust/Tauri 2.0.0、NSIS、Windows WebView2

## Global Constraints

- 目标平台仅为 Windows 10/11 x64。
- 只能删除 `D:\claudecode\cchaha\Project\deepseek` 项目路径内的内容。
- 不修改 Harness 产品功能，只修复发布、启动诊断和验收流程。
- 最终运行时不得包含完整上游源码或开发 workspace。
- 正常机器安装时间目标不超过 5 分钟。
- 未通过安装后冷启动测试时，不得报告安装包可交付。

---

### Task 1: 建立可复现的运行时验收器

**Files:**
- Create: `scripts/verify-release-runtime.mjs`
- Create: `scripts/tests/verify-release-runtime.test.mjs`

**Interfaces:**
- Consumes: `runtime/node.exe`、待验证目录中的 `lib/bin.js`
- Produces: `verifyRuntime({ nodePath, runtimePath, timeoutMs }): Promise<VerificationResult>`，其中结果包含 `url`、`pid`、`fileCount`、`bytes` 和 `startupMs`

- [ ] **Step 1: 编写失败测试**

测试缺入口、Node 提前退出和成功监听三个场景；使用临时目录内的小型 HTTP fixture，禁止依赖真实 Harness 才能验证测试器本身。

- [ ] **Step 2: 运行测试并确认失败**

Run: `node --test scripts/tests/verify-release-runtime.test.mjs`

Expected: FAIL，提示 `verify-release-runtime.mjs` 或导出函数不存在。

- [ ] **Step 3: 实现最小验收器**

验收器必须同时轮询 `http://127.0.0.1:<port>` 和监听子进程 `exit`；提前退出时返回 stderr 和退出码，不得只等待超时。

- [ ] **Step 4: 运行测试并确认通过**

Run: `node --test scripts/tests/verify-release-runtime.test.mjs`

Expected: PASS。

### Task 2: 生成精简且实体化的生产运行时

**Files:**
- Create: `scripts/build-release-runtime.mjs`
- Create: `scripts/release-runtime.config.json`
- Modify: `package.json`

**Interfaces:**
- Consumes: `harness-dist` 基础 deploy 结果、`upstream-source` 已构建 workspace 包
- Produces: `release-staging/harness-dist`，其内部不含指向项目其他位置的 junction 或 symlink

- [ ] **Step 1: 记录当前失败基线**

Run: `runtime\node.exe portable-release\harness-dist\lib\bin.js web --no-open --port 0`

Expected: FAIL，包含 `ERR_MODULE_NOT_FOUND` 和 `@deepseek-ai/dsh-app-boot`。

- [ ] **Step 2: 实现 staging 构建脚本**

脚本从 package manifest 和真实启动错误收敛 workspace 运行依赖，将各包的 `package.json`、`lib`、必要静态目录复制为普通文件；排除 `.git`、测试、源码、缓存、文档和 source map。

- [ ] **Step 3: 增加链接与规模检查**

构建完成后遍历 staging：发现 reparse point、junction 或越过 staging 根目录的链接时立即失败；同时输出文件数和展开体积。

- [ ] **Step 4: 使用 Task 1 验证真实 Harness**

Run: `node scripts/verify-release-runtime.mjs --node runtime/node.exe --runtime release-staging/harness-dist --timeout 120000`

Expected: PASS，输出监听地址、启动耗时、文件数和体积。

### Task 3: 修复桌面启动诊断和提前退出处理

**Files:**
- Modify: `src-tauri/src/lib.rs`
- Modify: `ui/main.js`

**Interfaces:**
- Consumes: Tauri resource directory 中的 `runtime/node.exe` 和 `harness-dist/lib/bin.js`
- Produces: `boot_url` 返回可用 URL；失败时返回包含日志路径和子进程状态的中文错误

- [ ] **Step 1: 修改 Rust 启动流程**

启动后在返回 URL 前短暂检查 `Child::try_wait()`；若 Node 已退出，读取日志尾部并返回错误。日志每次启动截断写入，避免旧错误污染判断。

- [ ] **Step 2: 修正前端健康检查**

移除 `mode: 'no-cors'` 和 30 秒后无条件跳转的分支；仅在 HTTP 请求真实成功时跳转，120 秒后显示日志路径。

- [ ] **Step 3: 编译桌面壳**

Run: `npm run tauri -- build --no-bundle`

Expected: release EXE 构建成功且无 Rust 编译警告。

### Task 4: 安全同步 Tauri resources

**Files:**
- Create: `scripts/prepare-tauri-resources.ps1`
- Modify: `package.json`

**Interfaces:**
- Consumes: 已通过验收的 `release-staging/harness-dist`、`runtime/node.exe`
- Produces: `src-tauri/resources/runtime` 和 `src-tauri/resources/harness-dist`

- [ ] **Step 1: 实现临时目录同步**

只在项目内创建 `src-tauri/resources.next`；复制完成并验证后，将当前 resources 改名为项目内备份，再替换为新目录。

- [ ] **Step 2: 验证 Tauri resources 冷启动**

Run: `node scripts/verify-release-runtime.mjs --node src-tauri/resources/runtime/node.exe --runtime src-tauri/resources/harness-dist --timeout 120000`

Expected: PASS，且文件数量不超过 staging 的 105%。

### Task 5: 构建并验收 NSIS 安装包

**Files:**
- Create: `scripts/test-installed-release.ps1`
- Modify: `progress.md`
- Modify: `task_plan.md`

**Interfaces:**
- Consumes: 已验证的 Tauri resources 和 NSIS 安装包
- Produces: 安装耗时、安装目录、启动结果、日志结果、文件大小及 SHA256 验收记录

- [ ] **Step 1: 生成 NSIS**

Run: `npm run tauri -- build --bundles nsis`

Expected: 生成新的 `DeepSeek Harness_0.1.0_x64-setup.exe`。

- [ ] **Step 2: 静默安装到测试目录**

测试脚本记录开始和结束时间，并检查安装器退出码；目标为 5 分钟内完成。测试目录必须位于项目路径内或当前用户应用目录内，删除操作只能针对脚本创建的目录。

- [ ] **Step 3: 启动安装后的 EXE**

启动后等待窗口进程和 Harness 子进程，检查最新日志不包含 `ERR_MODULE_NOT_FOUND`、panic 或提前退出，并确认本地 HTTP 服务可访问。

- [ ] **Step 4: 输出最终发布指标**

记录安装包字节数、SHA256、展开文件数、展开体积、安装耗时和冷启动耗时；只有全部通过才在 `task_plan.md` 标记安装验证完成。

## Self-Review

- 规格覆盖：安装慢由 Task 2/4/5 处理；闪退由 Task 1/2/3/5 处理；安装后真实验证由 Task 5 处理。
- 占位符检查：计划未包含 TBD、TODO 或未定义接口。
- 类型一致性：Task 1 的 `verifyRuntime` 同时服务 Task 2 和 Task 4；Task 5 使用相同的运行时验收语义。
