# DeepSeek Harness 桌面版

DeepSeek Harness 桌面版是一个适用于 Windows 10/11 x64 的独立桌面客户端。它将开源的 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 集成到桌面窗口中，用户无需打开命令行或单独安装 Node.js。

## 主要功能

- 双击应用即可打开 DeepSeek Harness。
- 在独立桌面窗口中使用 Web 界面。
- 内置运行环境，无需额外安装 Node.js。
- 自动选择本机可用端口，不影响其他程序。
- 服务仅运行在本机，不默认暴露到局域网。
- 支持 DeepSeek Harness 提供的智能体、文件操作、终端工具、技能和工作流能力。

## 使用方法

1. 下载 Windows 安装包。
2. 按安装向导完成安装。
3. 从桌面或开始菜单启动 **DeepSeek Harness**。
4. 按页面提示完成模型或 API 配置后即可使用。

## 系统要求

- Windows 10 或 Windows 11
- 64 位系统
- 建议保持系统 WebView2 运行时为最新版本

## 数据与隐私

- 客户端服务默认只监听本机地址 `127.0.0.1`。
- 配置和运行日志保存在当前 Windows 用户的应用数据目录中。
- 具体模型请求会按照你在 DeepSeek Harness 中配置的服务提供商执行。

## 日志与故障排查

如果应用无法启动或意外退出，请查看以下日志文件：

```text
%APPDATA%\ai.deepseek.harness.desktop\logs\harness.log
```

提交问题时，建议同时提供：

- Windows 版本
- 客户端版本
- 复现步骤
- 日志文件中的错误信息

请注意隐藏 API Key、密码和其他个人信息。

## 更新说明

DeepSeek Harness 官方仍处于开发者预览阶段，功能和配置可能持续变化。本桌面版会在经过验证后发布兼容的新版安装包。

## 开源许可

本项目是 DeepSeek Harness 的桌面封装。DeepSeek Harness 的源码、许可证和第三方依赖声明由上游项目维护，请同时遵守本项目及 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的相关许可条款。

## 问题反馈

请在本项目的 [Issues](https://github.com/BraumGGG/deepseek-Desktop/issues) 中提交问题或建议。
