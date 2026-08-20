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
    Stop-Process -Id $alive.Id -Force
}

$installerInfo = Get-Item -LiteralPath $installer
$hash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
$installedFiles = Get-ChildItem -LiteralPath $installDir -Recurse -File
[pscustomobject]@{
    Installer = $installerInfo.FullName
    InstallerBytes = $installerInfo.Length
    Sha256 = $hash
    InstallSeconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 2)
    InstalledFiles = $installedFiles.Count
    InstalledBytes = ($installedFiles | Measure-Object -Property Length -Sum).Sum
    Application = $app.FullName
    DesktopAliveAfter12Seconds = [bool]$alive
}
