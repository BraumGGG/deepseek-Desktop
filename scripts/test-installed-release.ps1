$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer = Join-Path $projectRoot 'src-tauri\target\release\bundle\nsis\DeepSeek Harness_0.1.0_x64-setup.exe'
$installDir = Join-Path $projectRoot 'install-test'
$installDir = [System.IO.Path]::GetFullPath($installDir)

if (-not $installDir.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean outside project root: $installDir"
}
if (-not (Test-Path -LiteralPath $installer)) {
    throw "Installer not found: $installer"
}

Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$installerProcess = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$installDir") -Wait -PassThru
$installerExitCode = $installerProcess.ExitCode
$stopwatch.Stop()
if ($installerExitCode -ne 0) {
    throw "Installer failed with exit code $installerExitCode"
}

$app = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'DeepSeek Harness.exe' -File | Select-Object -First 1
if (-not $app) {
    $app = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'deepseek-harness-desktop.exe' -File | Select-Object -First 1
}
if (-not $app) {
    throw "Installed application executable not found in $installDir"
}

$node = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'node.exe' -File | Select-Object -First 1
$entry = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'bin.js' -File |
    Where-Object { $_.FullName -like '*harness-dist*\lib\bin.js' } |
    Select-Object -First 1
if (-not $node -or -not $entry) {
    throw 'Installed runtime files are incomplete'
}
$runtimeDir = Split-Path (Split-Path $entry.FullName -Parent) -Parent

& $node.FullName (Join-Path $projectRoot 'scripts\verify-release-runtime.mjs') `
    --node $node.FullName `
    --runtime $runtimeDir `
    --timeout 120000
if ($LASTEXITCODE -ne 0) {
    throw 'Installed runtime cold-start verification failed'
}

$process = Start-Process -FilePath $app.FullName -PassThru
Start-Sleep -Seconds 12
$alive = Get-Process -Id $process.Id -ErrorAction SilentlyContinue
if (-not $alive) {
    throw 'Installed desktop application exited during cold start'
}
$null = $alive.CloseMainWindow()
if (-not $alive.WaitForExit(5000)) {
    $taskkill = Start-Process -FilePath 'taskkill.exe' -ArgumentList @('/PID', $alive.Id, '/T', '/F') -Wait -PassThru -WindowStyle Hidden
    if ($taskkill.ExitCode -ne 0) {
        Stop-Process -Id $alive.Id -Force -ErrorAction SilentlyContinue
    }
}

$installedFiles = Get-ChildItem -LiteralPath $installDir -Recurse -File
$installedFileCount = $installedFiles.Count
$installedBytes = ($installedFiles | Measure-Object -Property Length -Sum).Sum

Start-Sleep -Seconds 2
$residual = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -like "$installDir*" -or $_.CommandLine -like "*$installDir*"
}
if ($residual) {
    $details = ($residual | Select-Object ProcessId, Name, ExecutablePath, CommandLine | Out-String)
    throw ("Installed process tree remains after exit: " + $details)
}

$uninstaller = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'unins*.exe' -File |
    Select-Object -First 1
if (-not $uninstaller) {
    throw "Uninstaller not found in $installDir"
}
$uninstallProcess = Start-Process -FilePath $uninstaller.FullName -ArgumentList @('/S') -Wait -PassThru
if ($uninstallProcess.ExitCode -ne 0) {
    throw "Uninstaller failed with exit code $($uninstallProcess.ExitCode)"
}
Start-Sleep -Seconds 2
if (Test-Path -LiteralPath $installDir) {
    $remaining = Get-ChildItem -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($remaining) {
        throw "Uninstaller left files in project test directory: $installDir"
    }
    Remove-Item -LiteralPath $installDir -Force -ErrorAction SilentlyContinue
}

$installerInfo = Get-Item -LiteralPath $installer
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
[pscustomobject]@{
    Installer = $installerInfo.FullName
    InstallerBytes = $installerInfo.Length
    Sha256 = $hash
    InstallSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    InstalledFiles = $installedFileCount
    InstalledBytes = $installedBytes
    Application = $app.FullName
    DesktopAliveAfter12Seconds = [bool]$alive
    Uninstaller = $uninstaller.FullName
    UninstallExitCode = $uninstallProcess.ExitCode
    InstallTestDirectoryRemoved = -not (Test-Path -LiteralPath $installDir)
}
