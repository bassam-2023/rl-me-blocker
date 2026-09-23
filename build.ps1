# =====================================================================
#  build.ps1 - makes the release zip in dist\.
#  Usage: powershell -NoProfile -ExecutionPolicy Bypass -File build.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$app  = Join-Path $root 'src\RL-ME-Blocker.ps1'

$version = if ((Get-Content -LiteralPath $app -Raw -Encoding UTF8) -match "\`$AppVersion\s*=\s*'([^']+)'") { $Matches[1] }
           else { throw "Couldn't find `$AppVersion in $app" }

# Windows PowerShell 5.1 reads BOM-less scripts as ANSI, which garbles the Arabic text,
# while install.ps1 must have NO BOM so "irm | iex" works.
foreach ($f in 'src\RL-ME-Blocker.ps1', 'src\uninstall.ps1') {
    $b = [IO.File]::ReadAllBytes((Join-Path $root $f))
    if ($b.Length -lt 3 -or $b[0] -ne 0xEF -or $b[1] -ne 0xBB -or $b[2] -ne 0xBF) { throw "$f must be saved as UTF-8 with BOM" }
}
if (@([IO.File]::ReadAllBytes((Join-Path $root 'src\install.ps1')) | Where-Object { $_ -gt 127 }).Count) {
    throw 'src\install.ps1 must be pure ASCII'
}
$remote = Get-Content -LiteralPath (Join-Path $root 'ranges.json') -Raw | ConvertFrom-Json
if ($remote.latestVersion -ne $version) { Write-Warning "ranges.json latestVersion is $($remote.latestVersion), app is $version" }

$name    = "RL-ME-Blocker-v$version"
$dist    = Join-Path $root 'dist'
$staging = Join-Path $dist $name
Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
[void](New-Item -ItemType Directory -Path (Join-Path $staging 'src') -Force)

Copy-Item (Join-Path $root 'Install.cmd'), (Join-Path $root 'Uninstall.cmd'), (Join-Path $root 'README.md'),
          (Join-Path $root 'README.ar.md'), (Join-Path $root 'LICENSE') -Destination $staging
Copy-Item (Join-Path $root 'docs') -Destination $staging -Recurse
Copy-Item (Join-Path $root 'src\RL-ME-Blocker.ps1'), (Join-Path $root 'src\install.ps1'), (Join-Path $root 'src\uninstall.ps1') `
          -Destination (Join-Path $staging 'src')
Copy-Item (Join-Path $root 'src\fonts') -Destination (Join-Path $staging 'src') -Recurse

$zip = Join-Path $dist "$name.zip"
Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $zip
Remove-Item -LiteralPath $staging -Recurse -Force
Write-Host "Built $zip" -ForegroundColor Green
