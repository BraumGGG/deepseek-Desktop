$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$installer = Join-Path $projectRoot 'src-tauri\target\release\bundle\nsis\DeepSeek Harness_0.1.0_x64-setup.exe'
$installDir = [System.IO.Path]::GetFullPath((Join-Path $projectRoot 'install-overlay-test'))
if (-not $installDir.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to operate outside project root: $installDir"
}
if (-not (Test-Path -LiteralPath $installer)) { throw "Installer not found: $installer" }
Remove-Item -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue

$first = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$installDir") -Wait -PassThru
if ($first.ExitCode -ne 0) { throw "Initial install failed: $($first.ExitCode)" }
$app = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'deepseek-harness-desktop.exe' -File | Select-Object -First 1
if (-not $app) { throw "Installed executable not found: $installDir" }
$running = Start-Process -FilePath $app.FullName -PassThru
Start-Sleep -Seconds 8
if (-not (Get-Process -Id $running.Id -ErrorAction SilentlyContinue)) { throw 'Initial installed app did not stay alive' }

$overlayWatch = [System.Diagnostics.Stopwatch]::StartNew()
$second = Start-Process -FilePath $installer -ArgumentList @('/S', "/D=$installDir") -Wait -PassThru
$overlayWatch.Stop()
if ($second.ExitCode -ne 0) { throw "Overlay install failed: $($second.ExitCode)" }
Start-Sleep -Seconds 3
$old = Get-Process -Id $running.Id -ErrorAction SilentlyContinue
if ($old) { throw "Overlay install left the old desktop process alive: PID $($running.Id)" }
$remaining = Get-CimInstance Win32_Process | Where-Object {
    $_.ExecutablePath -like "$installDir*" -or $_.CommandLine -like "*$installDir*"
}
if ($remaining) { throw 'Overlay install left processes from the old installation' }

$newApp = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'deepseek-harness-desktop.exe' -File | Select-Object -First 1
if (-not $newApp) { throw 'Overlay install removed the application executable' }
$new = Start-Process -FilePath $newApp.FullName -PassThru
Start-Sleep -Seconds 12
$newAlive = Get-Process -Id $new.Id -ErrorAction SilentlyContinue
if (-not $newAlive) { throw 'Application did not start after overlay install' }
$null = $newAlive.CloseMainWindow()
if (-not $newAlive.WaitForExit(5000)) {
    Start-Process taskkill.exe -ArgumentList @('/PID', $newAlive.Id, '/T', '/F') -Wait -WindowStyle Hidden | Out-Null
}

$uninstaller = Get-ChildItem -LiteralPath $installDir -Recurse -Filter 'unins*.exe' -File | Select-Object -First 1
if (-not $uninstaller) { throw 'Overlay uninstaller not found' }
$uninstall = Start-Process -FilePath $uninstaller.FullName -ArgumentList @('/S') -Wait -PassThru
if ($uninstall.ExitCode -ne 0) { throw "Overlay uninstall failed: $($uninstall.ExitCode)" }
Start-Sleep -Seconds 2
if (Test-Path -LiteralPath $installDir) {
    $left = Get-ChildItem -LiteralPath $installDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($left) { throw 'Overlay uninstall left files behind' }
    Remove-Item -LiteralPath $installDir -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    OverlayInstallSeconds = [math]::Round($overlayWatch.Elapsed.TotalSeconds, 2)
    OldProcessStopped = -not [bool]$old
    NewProcessAliveAfter12Seconds = [bool]$newAlive
    OverlayUninstallExitCode = $uninstall.ExitCode
    OverlayDirectoryRemoved = -not (Test-Path -LiteralPath $installDir)
}
