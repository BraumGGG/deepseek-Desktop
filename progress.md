# 进度记录

## 2026-08-20

- 完成需求收敛：独立桌面窗口、Windows 10/11 x64、轻量便携 ZIP。
- 完成方案比较：推荐 Tauri + Node sidecar。
- 创建设计说明和实施计划。
- 获取并检查 `@deepseek-ai/dsh@0.1.0-rc.7` npm 包，确认入口为 `lib/bin.js`，Web 启动命令为 `dsh web`。
- GitHub 克隆因连接重置失败；npm 安装完整依赖在镜像端长时间未完成，已停止挂起进程。
- 创建 Tauri 桌面壳、启动协议、基础窗口页面和运行时准备脚本。
- 安装 `@tauri-apps/cli@2.11.4` 成功。
- `npx tauri info` 确认 WebView2、MSVC 和 Windows x64 环境可用。
- 发现默认 Rust stable toolchain manifest 损坏，已切换到已安装的 1.85.0；cargo 编译随后卡在 crates.io 索引下载，尚未完成。
- 修正 Tauri bundle 资源路径为项目根目录的 `runtime/` 和 `harness/`。
- 网络恢复后从 GitHub ZIP 获取官方源码，安装 935 个 workspace 包并成功完成 `pnpm run build:official`。
- 使用 `pnpm deploy --prod --legacy` 生成可分发的 `harness-dist`，补入已构建的 Web `dist/`。
- 用项目内 `runtime/node.exe` 启动 `harness-dist/lib/bin.js web --no-open --port 0` 成功监听随机端口。
- 最终 Tauri 资源目录改为直接打包 `harness-dist`，避免复制大型 node_modules 时的合并问题。
- 添加应用图标并成功编译 Tauri debug EXE。
- 通过兼容性降级将 Tauri 依赖锁定到可用 Rust 1.85 的组合：tauri 2.0.0、tauri-utils 2.0.0、tauri-runtime 2.0.0 等。
- 成功生成 release EXE：`src-tauri/target/release/deepseek-harness-desktop.exe`。
- NSIS 安装器因下载官方 NSIS 压缩包超时失败；本阶段先交付 EXE 和资源目录测试路径。
- 2026-08-20：网络恢复后重新执行 NSIS 打包，NSIS 3.11 与 tauri-utils 下载、校验和解压成功。
- 成功生成 `DeepSeek Harness_0.1.0_x64-setup.exe`，大小 24.76 MB，SHA256 为 `343C2477E9EB0BA253248E8F844E3BBC0C0A6E87B9D602B388F18BE4AD7C6BA2`。
- 将 NSIS 安装器语言固定为 `SimpChinese`，关闭语言选择器并重新生成安装包。
- 新安装包约 24.74 MB，SHA256 为 `30FEBA5C8617FC183DABAB160B332AED85D093DAA2273CADA753DDA8DB2D7075`。
- 修复安装后资源路径错误：将 runtime 和 harness-dist 放入 `src-tauri/resources/`，NSIS 现在安装到 `resources/`，启动器同时兼容旧路径。
- Windows 子进程增加 `CREATE_NO_WINDOW`，不再弹出黑色 Node 控制台窗口。
- 重新生成安装包，大小约 45.8 MB，SHA256 为 `DBB18EB4E1411A1DED0950402D2F00D43AB701038EA6A0F6529AD953AABC21EC`。
- 最终发布资源目录已直接用内置 `runtime/node.exe` 启动 `harness-dist/lib/bin.js web --no-open --port 0` 验证成功；peer workspace 依赖闭包完整。
- 最终 NSIS 安装包已完成生成并核对：47,998,386 字节，SHA256 为 `dbb18eb4e1411a1ded0950402d2f00d43ab701038ea6a0f6529ad953aabc21ec`。
- 用户最终实测确认上述 47,998,386 字节安装包仍存在安装约一小时、启动闪退问题，因此该哈希版本已废弃，不再视为可交付产物。
- 重新复现便携目录启动，确认缺少 `@deepseek-ai/dsh-app-boot`；同时确认旧 Tauri resources 展开为 408,223,967 字节、56,001 个文件，是 NSIS 安装极慢的直接原因。
- 新增运行时验收器及 3 个自动测试，能够检测入口缺失、Node 提前退出和 HTTP 服务成功监听。
- 新增精简运行时构建器，从已验证运行时和官方 workspace 构建产物递归生成实体化依赖闭包，排除 pnpm 存储、循环 junction、测试、文档和类型声明。
- 精简运行时包含 436 个包、12,023 个文件、132,525,833 字节；使用内置 Node 冷启动验证成功。
- Tauri 启动流程改为等待本地端口真实监听，并在 Node 提前退出时显示退出码、日志路径和日志尾部；前端不再盲等后跳转。
- 新 NSIS 安装包为 43,061,065 字节，SHA256 为 `874AB242EC471EFD27A4DAB1A20A78C8F4BD61687E9C4C4477219460797D159D`。
- 新安装包在项目内隔离目录完成真实静默安装：耗时 17.33 秒，安装后 12,026 个文件、226,045,745 字节；安装后运行时 3.46 秒启动，桌面进程 12 秒后仍存活，日志正常且测试结束无残留进程。
