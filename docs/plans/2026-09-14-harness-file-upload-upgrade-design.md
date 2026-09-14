# Harness 文件上传升级设计说明

## 背景与目标

当前 Tauri 客户端内置 `@deepseek-ai/dsh@0.1.0-rc.8`，前端仅支持图片上传。官方 Harness 主线已更新到 `0.1.5-rc.2`，并新增 `dsh-client-file-upload`、`dsh-client-ui-attachment` 及本地文件附件存储。目标是在保留现有 Tauri 外壳的前提下，升级内置 Harness 生产资源，使 PDF、TXT、DOCX 等普通文件可以上传，并保持启动、覆盖安装和用户数据稳定。

## 现状与约束

- 桌面宿主：Tauri 2 + Rust，入口为 `src-tauri/src/lib.rs`。
- 内置资源：`src-tauri/resources/harness-dist`，由脚本生成并随 NSIS 打包。
- 资源必须是生产依赖闭包，不能复制官方开发目录中的完整 `node_modules`。
- 用户数据必须位于应用数据目录，不能写入安装目录。
- 目标平台为 Windows 10/11 x64。

## 方案对比

### 方案一：直接复制官方开发工作区

- 优点：实现最快。
- 缺点：会带入数 GB 开发依赖，无法接受；还可能混入测试和平台无关包。

### 方案二：复用现有精简闭包脚本并接入官方生产构建（推荐）

- 优点：保留 Tauri 外壳和现有验证流程，只替换 Harness 资源；可控体积；能包含新版文件上传依赖。
- 缺点：需要补齐新版依赖闭包和前端 dist 的复制规则。

### 方案三：迁移到 `dataelement/dsh-desktop` 的 Electron 架构

- 优点：拥有更完整的 Safe Mode、升级、恢复和发布体系。
- 缺点：改动范围大，不能作为当前文件上传问题的快速修复；会引入新的桌面技术栈。

## 推荐方案

采用方案二：保留 Tauri 宿主，使用官方 `0.1.5-rc.2` 构建产物和生产依赖闭包，更新资源打包脚本与版本元数据，增加普通文件上传和重启回归测试。后续可单独引入 Safe Mode 和自动更新能力。

## 详细设计

### 架构

官方源码在隔离目录构建 `build:official`，生成 CLI、Web 前端和各 workspace 包的 `lib`。资源打包脚本只复制 CLI 运行所需的生产包、`apps/web/dist` 静态资源、配置文件及现有 Node runtime，排除 `node_modules`、测试、源码地图和开发工具。

### 关键组件

- `scripts/build-release-runtime.mjs`：根据根 manifest 解析依赖闭包；对官方 workspace 包优先使用构建后的 `lib` 和 package manifest。
- `scripts/prepare-tauri-resources.ps1`：把精简运行时和 Web dist 组装到 `src-tauri/resources`，运行冷启动校验。
- `src-tauri/src/lib.rs`：继续负责端口、进程树和窗口生命周期；只在需要时修正用户数据路径或启动环境。
- `src-tauri/tauri.conf.json`：维持资源清单，更新应用版本。

### 数据流

1. 官方源码构建生成 `apps/cli/lib`、`apps/web/dist` 和 workspace `lib`。
2. 生产闭包脚本解析 `@deepseek-ai/dsh` 及其依赖，复制到 `release-staging/harness-dist`。
3. Tauri 资源准备脚本复制 Node runtime、Harness 目录和前端静态资源。
4. Rust 宿主启动 `node.exe lib/bin.js web --no-open --port <free-port>`。
5. Web UI 通过新版 `file-upload` 服务上传文件，附件存储写入用户应用数据目录。

### 异常与边界处理

- 任一必需包缺失时构建立即失败，不生成可发布资源。
- 资源冷启动失败时不替换当前已知可用资源。
- 上传失败显示前端错误状态，不影响已有会话。
- 启动超时或进程异常退出时保留日志并终止整个进程树。
- 不把用户会话、凭据或附件数据写入安装目录。

### 测试策略

- 构建级：验证官方版本、依赖闭包、无符号链接、文件数量和资源体积。
- 启动级：冷启动 HTTP 冒烟、端口监听、退出后再次启动。
- UI 级：确认文件选择器接受 PDF/TXT/DOCX，图片上传保持可用。
- 安装级：NSIS 安装、覆盖安装、卸载和用户数据保留。

## 风险与待确认项

- 官方 `0.1.5-rc.2` 要求 Node `22.19+`，当前开发机为 `22.18.0`；打包使用的 Windows runtime 版本必须单独核对。
- 新版生产闭包可能显著增大安装包，需要记录体积变化并设置合理上限。
- 官方开发者预览版本可能改变配置或附件协议，发布前必须完成实机上传验证。
