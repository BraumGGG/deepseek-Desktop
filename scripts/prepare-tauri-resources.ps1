$ErrorActionPreference = 'Stop'

$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceRuntime = Join-Path $projectRoot 'runtime'
$sourceHarness = Join-Path $projectRoot 'release-staging\harness-dist'
$resources = Join-Path $projectRoot 'src-tauri\resources'
$next = Join-Path $projectRoot 'src-tauri\resources.next'
$backup = Join-Path $projectRoot 'src-tauri\resources.previous'

foreach ($path in @($resources, $next, $backup)) {
    $full = [System.IO.Path]::GetFullPath($path)
    if (-not $full.StartsWith($projectRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to operate outside project root: $full"
    }
}

if (-not (Test-Path -LiteralPath (Join-Path $sourceRuntime 'node.exe'))) {
    throw 'Missing runtime/node.exe'
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceHarness 'lib\bin.js'))) {
    throw 'Missing release-staging/harness-dist/lib/bin.js'
}

Remove-Item -LiteralPath $next -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $next 'runtime') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceRuntime 'node.exe') -Destination (Join-Path $next 'runtime\node.exe')
Copy-Item -LiteralPath $sourceHarness -Destination (Join-Path $next 'harness-dist') -Recurse

& (Join-Path $projectRoot 'runtime\node.exe') `
    (Join-Path $projectRoot 'scripts\verify-release-runtime.mjs') `
    --node (Join-Path $next 'runtime\node.exe') `
    --runtime (Join-Path $next 'harness-dist') `
    --timeout 120000
if ($LASTEXITCODE -ne 0) {
    throw 'resources.next cold-start verification failed'
}

Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $resources) {
    Move-Item -LiteralPath $resources -Destination $backup
}
Move-Item -LiteralPath $next -Destination $resources
Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue

Write-Output "Tauri resources replaced: $resources"
