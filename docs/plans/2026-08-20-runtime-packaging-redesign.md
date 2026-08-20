# DeepSeek Harness Windows 发布结构重建设计

## 背景与目标

现有 NSIS 安装包压缩后约 45 MB，但包含约 470 MB、56,001 个发布文件，导致 Windows 安装过程极慢。现有便携目录还会因缺少 `@deepseek-ai/dsh-app-boot` 在启动阶段退出，因此当前安装包不可交付。

本次目标是重新建立可重复的 Windows x64 发布流程，使最终安装包满足：

- 不包含上游源码、开发依赖或完整 pnpm workspace。
- 安装文件数量显著降低，正常机器安装时间目标不超过 5 分钟。
- 使用安装后的真实目录启动 Harness，而不是只验证源码目录。
- 构建阶段自动检测缺包、提前退出和服务未监听端口。
- 只有通过冷启动验收后才生成并标记最终安装包。

## 现状与约束

- 桌面壳使用 Tauri 2.0.0，目标为 Windows 10/11 x64。
- Harness 固定使用已构建的 `0.1.0-rc.8`，Node runtime 随包分发。
- pnpm deploy 产生的链接结构不能直接作为 NSIS 资源；安装器不会可靠保留项目内 junction 语义。
- 当前项目目录不是 Git 仓库，因此本轮无法创建提交。
- 只能删除项目目录内的旧构建产物。

## 方案对比

### 方案一：继续打包完整 workspace

- 优点：不容易遗漏动态依赖。
- 缺点：约 56,001 个文件，安装不可接受；包含大量无关内容。

### 方案二：精简并实体化运行依赖闭包

- 优点：保留现有 Tauri 架构；安装包和运行时更小；可以逐项验证依赖。
- 缺点：需要可靠的 staging 脚本处理 pnpm 链接和 workspace peer dependencies。

### 方案三：改为 Electron + ASAR

- 优点：JavaScript 依赖封装成熟，文件数量容易控制。
- 缺点：需要重写桌面壳，包体和内存占用增加，超出本次修复范围。

## 推荐方案

采用方案二。建立独立的 `release-staging` 目录，通过脚本从官方构建结果生成实体化、只读的生产运行时。脚本随后使用随包 Node 启动 `dsh web`，只有服务成功监听后才同步到 `src-tauri/resources` 并执行 NSIS 构建。

## 详细设计

### 架构

发布流程分为四层：官方构建产物、精简 staging、Tauri resources、NSIS 安装包。每一层都有独立检查，禁止直接把源码 `node_modules` 复制进 Tauri resources。

### 关键组件

- `scripts/build-release-runtime.mjs`：生成实体化生产运行时，复制必要的 workspace 包和 Web 静态资源。
- `scripts/verify-release-runtime.mjs`：检查文件数量、入口文件、关键依赖，并实际启动本地服务。
- `scripts/prepare-tauri-resources.ps1`：验证通过后，以项目路径内的临时目录原子替换 Tauri resources。
- Tauri 启动器：记录启动路径、子进程退出码和 stderr；服务提前退出时直接显示可诊断错误。

### 数据流

1. 从固定的 Harness 构建目录生成 `release-staging/harness-dist`。
2. 将 pnpm 链接解析成真实目录，排除测试、源码映射、缓存和开发工具。
3. 使用 `runtime/node.exe` 启动 staging 中的 `lib/bin.js web --no-open --port <port>`。
4. 轮询 HTTP 服务，并同时监控 Node 子进程是否提前退出。
5. 验证通过后同步到 `src-tauri/resources`，再生成 NSIS。
6. 在临时安装目录执行静默安装，启动安装后的 EXE，并验证 Harness 日志和监听端口。

### 异常与边界处理

- 缺少任意运行依赖：验证脚本非零退出，不生成安装包。
- Node 提前退出：保存完整 stderr 和退出码，桌面 UI 不再等待 120 秒后才提示。
- 文件数量异常增长：超过设定阈值时构建失败，防止再次打入完整 workspace。
- 旧安装包：从发布清单中明确标记为废弃，不覆盖成“修复版”。

### 测试策略

- staging 入口与关键包静态检查。
- staging 目录真实 Node 冷启动测试。
- Tauri resources 目录冷启动测试。
- NSIS 静默安装耗时与退出码测试。
- 安装后 EXE 启动、日志、端口和进程生命周期测试。
- 记录最终文件数、展开体积、安装包大小和 SHA256。

## 风险与待确认项

- Harness 使用动态插件解析，静态分析不能替代真实启动测试。
- 部分功能可能仅在选择具体 agent/provider 后加载额外包，因此除首页启动外还应至少执行一次基础配置加载测试。
- 未签名安装包仍可能触发 Windows SmartScreen，但这与本次闪退无关。
