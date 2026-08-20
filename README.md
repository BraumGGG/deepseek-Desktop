# DeepSeek Harness Desktop

Windows 10/11 x64 desktop wrapper for the open-source [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

## What It Does

- Starts the bundled Harness Web UI in an independent desktop window.
- Ships a portable Node runtime; users do not need to install Node.js.
- Keeps the Harness service on `127.0.0.1` and chooses an available port.
- Produces a Chinese NSIS installer after a real cold-start verification.

## Development

Requirements:

- Windows 10/11 x64
- Node.js 22+
- Rust stable compatible with the pinned Tauri dependencies
- pnpm 11+

Install desktop dependencies and run the shell:

```powershell
npm install
npm run dev
```

## Release Build

The release process intentionally does not commit generated runtimes or installers:

```powershell
pnpm install
pnpm run build:official
pnpm --filter @deepseek-ai/dsh deploy --prod --legacy
npm run release:runtime
npm run verify:runtime
npm run release:resources
npx tauri build --bundles nsis
```

The runtime staging step materializes the workspace dependency closure, removes pnpm links and development-only files, and runs a cold-start check before Tauri packaging.

## Logs

Startup logs are written to the current user's application data directory under `logs/harness.log`.

## Upstream License

DeepSeek Harness is a separate open-source project. Its source, license, notices, and update policy are maintained by the upstream project. This repository contains the desktop wrapper and release tooling.
