# 研究发现

## 已确认

- 用户明确选择独立桌面窗口。
- 用户接受首版只支持 Windows 10/11 x64。
- 用户优先考虑免费分享、包体积小和操作简单。
- 推荐 Tauri + Node sidecar；发布形式为便携 ZIP。

## 待验证

- DeepSeek Harness 的具体版本、`dsh web` 入口和可分发构建产物。
- Node 依赖中是否包含需要额外处理的原生模块。
- Windows 目标机上的 WebView2 运行时覆盖情况。

## 实现阶段发现

- GitHub shallow clone 在当前网络环境中连接被重置。
- npm registry 可查询到 `@deepseek-ai/dsh@0.1.0-rc.7`，包本身约 33 KB 压缩、117 KB 解压，但完整依赖树需要单独安装和体积测量。
- 本地 Node 22、pnpm 11 和 Cargo 可用；Rust stable 工具链当前缺少可用 manifest，Tauri 编译尚未验证。
- `rustup default 1.85.0-x86_64-pc-windows-msvc` 可绕过损坏的 stable 目录；之后 `cargo build` 卡在更新 crates.io 索引，属于网络依赖下载阻塞。
- Tauri bundle 资源路径相对于 `src-tauri/tauri.conf.json`，已改为 `../runtime` 和 `../harness`，对应项目根目录发布资源。
- 官方生产构建要求存在 Git 提交哈希；从 ZIP 解压后初始化本地 Git 仓库即可构建。
- `pnpm --filter @deepseek-ai/dsh deploy --prod --legacy` 可生成约 13 MB 的生产依赖目录；额外 Web dist 后仍可由固定 Node runtime 启动。
- Tauri 2.0.0 与当前 Rust 1.85 兼容，但需锁定一组旧依赖；直接使用最新 Tauri 2 依赖会要求 Rust 1.88。
- `npx tauri build --no-bundle` 已生成 release EXE；`npx tauri build --bundles nsis` 的 NSIS 下载步骤超时，不代表 Rust 编译失败。
- 重新执行后 NSIS 安装器成功生成，压缩后约 24.76 MB，满足轻量分享目标。
- 安装器脚本曾显示资源落在 `_up_` 前缀目录，导致安装后 EXE 找不到资源；改为 `src-tauri/resources` 后脚本显示为 `resources/runtime` 和 `resources/harness-dist`。
- Node 子进程默认会创建控制台窗口，已使用 Windows `CREATE_NO_WINDOW` 标志隐藏。
- 首次安装后超时的根因是 `pnpm deploy --prod --legacy` 未带入 Harness workspace peer dependencies，而不是端口或 WebView2；已补齐官方构建包并在最终发布资源目录实测启动成功。
- 启动失败时 stdout/stderr 现在写入 `%LOCALAPPDATA%\\DeepSeek Harness\\logs\\harness.log`，UI 等待时间提高到 120 秒，便于一次定位问题。
- 旧安装包虽只有约 45 MB，但 resources 中包含 56,001 个文件、约 389 MB Harness 数据；压缩体积不能代表安装成本，NSIS 的逐文件创建导致安装极慢。
- `pnpm deploy --prod --legacy` 会保留指向官方 workspace 的 junction，单独复制后会缺少 `@deepseek-ai/dsh-app-boot` 等包；直接解引用整个 workspace 又会产生循环和大量重复文件。
- 可行发布方式是从已构建 manifest 递归计算依赖闭包，将内部 workspace 包与外部 npm 包实体化到单一顶层 `node_modules`，并排除类型声明、测试、文档和 pnpm 存储。
- 精简后的实际安装测试为 17.33 秒，安装后冷启动成功；新包 SHA256 为 `874AB242EC471EFD27A4DAB1A20A78C8F4BD61687E9C4C4477219460797D159D`。
