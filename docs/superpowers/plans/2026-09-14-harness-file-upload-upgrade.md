# Harness File Upload Upgrade Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade the Tauri desktop client from the bundled Harness `0.1.0-rc.8` runtime to the official `0.1.5-rc.2` production closure so ordinary files can be uploaded.

**Architecture:** Keep the existing Rust/Tauri host and replace only the embedded Harness runtime and Web assets. Build the official monorepo in an isolated checkout, package only production dependencies and generated `lib`/`dist`, then run the existing cold-start and installer checks.

**Tech Stack:** Tauri 2, Rust, Windows PowerShell, Node.js, pnpm, official DeepSeek Harness build scripts.

## Global Constraints

- Target Windows 10/11 x64.
- Keep the Tauri host architecture.
- Do not copy development `node_modules` into the release runtime.
- Preserve user data outside the installation directory.
- Do not replace known-good resources until cold-start validation passes.

---

### Task 1: Prepare and pin the official upstream build

**Files:**
- Modify: `scripts/release-runtime.config.json`
- Modify: `README.md`

**Interfaces:**
- Produces an isolated official build at `upstream-source` or an equivalent ignored checkout with version `0.1.5-rc.2`.

- [ ] **Step 1: Fetch and verify the upstream commit**

Run:

```powershell
git -C upstream-source fetch origin master
git -C upstream-source checkout --detach c291e79
Get-Content upstream-source/package.json | Select-String '"version"'
```

Expected: root version `0.1.5-rc.2`.

- [ ] **Step 2: Install and build official artifacts**

Run:

```powershell
pnpm install --frozen-lockfile
pnpm run build:official
```

Expected: `apps/cli/lib/bin.js` and `apps/web/dist/index.html` exist.

- [ ] **Step 3: Record the source version**

Update the project release metadata to state that the embedded Harness is `0.1.5-rc.2`.

- [ ] **Step 4: Commit**

```powershell
git add scripts/release-runtime.config.json README.md
git commit -m "build: pin official harness 0.1.5-rc.2"
```

### Task 2: Build a production-only runtime closure

**Files:**
- Modify: `scripts/build-release-runtime.mjs`
- Modify: `scripts/release-runtime.config.json`
- Test: `scripts/verify-release-runtime.mjs`

**Interfaces:**
- `build-release-runtime.mjs` produces `release-staging/harness-dist` containing `lib`, `config`, `web frontend dist`, package manifests, and only required runtime dependencies.

- [ ] **Step 1: Add a closure inventory check**

Verify the generated tree contains these packages and no development-only tree:

```powershell
Test-Path release-staging/harness-dist/node_modules/@deepseek-ai/dsh-client-file-upload
Test-Path release-staging/harness-dist/node_modules/@deepseek-ai/dsh-client-ui-attachment
Test-Path release-staging/harness-dist/node_modules/@deepseek-ai/dsh-web-frontend/dist/index.html
Test-Path release-staging/harness-dist/node_modules/.pnpm
```

Expected: first three are `True`; `.pnpm` is `False`.

- [ ] **Step 2: Implement workspace package resolution**

Resolve `@deepseek-ai/*` packages from the official build output and copy only their declared runtime files and dependencies. Keep `excludeNames` and `excludeExtensions` active for tests, maps, TypeScript sources, and package-manager metadata.

- [ ] **Step 3: Generate and inspect the closure**

Run:

```powershell
node scripts/build-release-runtime.mjs
node scripts/verify-release-runtime.mjs --node runtime/node.exe --runtime release-staging/harness-dist --timeout 120000
```

Expected: JSON metrics are printed and cold start succeeds.

- [ ] **Step 4: Commit**

```powershell
git add scripts/build-release-runtime.mjs scripts/release-runtime.config.json
git commit -m "build: package production harness closure"
```

### Task 3: Replace Tauri resources and validate ordinary file upload

**Files:**
- Modify: `scripts/prepare-tauri-resources.ps1`
- Modify: `src-tauri/tauri.conf.json`
- Create: `scripts/verify-file-upload-assets.mjs`

**Interfaces:**
- `verify-file-upload-assets.mjs` exits nonzero when the generated frontend lacks the file-upload bundle or ordinary-file MIME handling.

- [ ] **Step 1: Write the asset verification script**

The script must inspect generated JS under `release-staging/harness-dist/node_modules/@deepseek-ai/dsh-web-frontend/dist/assets`, require the file-upload markers, and print matched asset names.

- [ ] **Step 2: Run the verifier before replacement**

Run:

```powershell
node scripts/verify-file-upload-assets.mjs
```

Expected: PASS and output naming the file-upload and attachment assets.

- [ ] **Step 3: Prepare Tauri resources**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/prepare-tauri-resources.ps1
```

Expected: `src-tauri/resources` is replaced only after cold-start verification.

- [ ] **Step 4: Update desktop version metadata**

Set the desktop version to the next release version agreed for this upgrade and keep the embedded Harness version in release notes.

- [ ] **Step 5: Commit**

```powershell
git add scripts/prepare-tauri-resources.ps1 src-tauri/tauri.conf.json scripts/verify-file-upload-assets.mjs src-tauri/resources
git commit -m "feat: enable ordinary file uploads in desktop runtime"
```

### Task 4: Run packaged lifecycle and installer regression checks

**Files:**
- Modify: `README.md`
- Test: existing lifecycle and packaging scripts under `scripts/` and `src-tauri/`

**Interfaces:**
- Produces a verified Windows NSIS installer with the upgraded Harness runtime.

- [ ] **Step 1: Build the installer**

Run:

```powershell
pnpm run build
```

Expected: NSIS installer is generated under `src-tauri/target/release/bundle/nsis`.

- [ ] **Step 2: Verify package contents**

Check that the installer contains `runtime/node.exe`, `harness-dist/lib/bin.js`, the Web dist, and file-upload packages.

- [ ] **Step 3: Execute lifecycle tests**

Run the existing install, overlay-install, uninstall, and process-cleanup checks. Repeat launch after two full exits and inspect `%APPDATA%\\ai.deepseek.harness.desktop\\logs\\harness.log`.

- [ ] **Step 4: Perform manual UI acceptance**

In the packaged application, select a `.pdf`, `.txt`, and `.docx`; confirm each appears as an attachment card, uploads successfully, and can be removed/retried. Confirm image upload still works.

- [ ] **Step 5: Commit release documentation**

```powershell
git add README.md
git commit -m "docs: document ordinary file upload support"
```

### Task 5: Publish the verified release

**Files:**
- Modify: `RELEASE.md`

- [ ] **Step 1: Calculate installer hash and size**

Run:

```powershell
Get-FileHash src-tauri/target/release/bundle/nsis/*setup.exe -Algorithm SHA256
Get-Item src-tauri/target/release/bundle/nsis/*setup.exe | Select-Object Name,Length
```

- [ ] **Step 2: Create a version tag and GitHub Release**

Use the existing GitHub release workflow, attach the verified installer, and state that the embedded Harness is `0.1.5-rc.2` with ordinary file upload support.

- [ ] **Step 3: Verify the public download**

Use an HTTP HEAD request against the release asset and confirm status `200`.

- [ ] **Step 4: Commit release notes**

```powershell
git add RELEASE.md
git commit -m "release: publish desktop file upload upgrade"
```
