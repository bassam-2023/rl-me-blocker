# =====================================================================
#  install.ps1 - installs RL ME Blocker for the current user.
#  Run by Install.cmd from the release zip, or straight from GitHub:
#    irm https://raw.githubusercontent.com/bassam-2023/rl-me-blocker/main/src/install.ps1 | iex
#  No admin needed here; the app asks for it when it starts.
#  Keep this file pure ASCII with no BOM, or "irm | iex" breaks.
# =====================================================================

# Wrapped in a script block so nothing leaks into the user's session under "irm | iex"
& {
    $ErrorActionPreference = 'Stop'
    $AppName    = 'RL ME Blocker'
    $RawBase    = 'https://raw.githubusercontent.com/bassam-2023/rl-me-blocker/main/src'
    $InstallDir = Join-Path $env:LOCALAPPDATA 'RL-ME-Blocker'
    $Files      = 'RL-ME-Blocker.ps1', 'uninstall.ps1', 'fonts/OFL.txt', 'fonts/Tajawal-Regular.ttf',
                  'fonts/Tajawal-Medium.ttf', 'fonts/Tajawal-Bold.ttf', 'fonts/Tajawal-Black.ttf'
    $PsExe      = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    Add-Type -AssemblyName PresentationFramework

    try {
        Write-Host ''
        Write-Host "  Installing $AppName..." -ForegroundColor Cyan
        [void](New-Item -ItemType Directory -Path (Join-Path $InstallDir 'fonts') -Force)

        # From the zip the files sit next to this script; via "irm | iex" there is no script
        # folder, so they're downloaded from GitHub instead.
        $local = if ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'RL-ME-Blocker.ps1'))) { $PSScriptRoot }
        if (-not $local) {
            [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        }
        foreach ($f in $Files) {
            $dest = Join-Path $InstallDir $f
            # A running app keeps its font files open, and a font file never changes under
            # the same name, so ones already installed are left alone
            if ($f -like 'fonts/*' -and (Test-Path -LiteralPath $dest)) { continue }
            if ($local) { Copy-Item -LiteralPath (Join-Path $local $f) -Destination $dest -Force }
            else        { Invoke-WebRequest -UseBasicParsing -Uri "$RawBase/$f" -OutFile $dest }
            Unblock-File -LiteralPath $dest   # drop the "downloaded from the internet" mark
        }

        $app     = Join-Path $InstallDir 'RL-ME-Blocker.ps1'
        $appArgs = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$app`""
        $version = if ((Get-Content -LiteralPath $app -Raw -Encoding UTF8) -match "\`$AppVersion\s*=\s*'([^']+)'") { $Matches[1] } else { '1.0.0' }

        # Desktop + Start menu shortcuts. The app swaps their icon to show the live status.
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($dir in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) {
            $lnk = $wsh.CreateShortcut((Join-Path $dir "$AppName.lnk"))
            $lnk.TargetPath       = $PsExe
            $lnk.Arguments        = $appArgs
            $lnk.WorkingDirectory = $InstallDir
            $lnk.IconLocation     = "$env:SystemRoot\System32\shell32.dll,47"   # padlock, until the app sets its own
            $lnk.Description      = 'Block or allow Rocket League Middle East (ME6) servers'
            $lnk.WindowStyle      = 7   # minimized, so no console flashes up
            $lnk.Save()
        }

        # Entry in Settings > Apps, so it can be removed like any other program
        $key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RL-ME-Blocker'
        [void](New-Item -Path $key -Force)
        $props = @{
            DisplayName     = $AppName
            DisplayVersion  = $version
            Publisher       = 'bassam-2023'
            InstallLocation = $InstallDir
            DisplayIcon     = "$env:SystemRoot\System32\shell32.dll,47"
            UninstallString = "`"$PsExe`" -NoProfile -ExecutionPolicy Bypass -File `"$(Join-Path $InstallDir 'uninstall.ps1')`""
            URLInfoAbout    = 'https://github.com/bassam-2023/rl-me-blocker'
        }
        foreach ($p in $props.GetEnumerator()) { Set-ItemProperty -Path $key -Name $p.Key -Value $p.Value }
        Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord

        Write-Host "  Done. $AppName is on your Desktop and in the Start menu." -ForegroundColor Green
        Write-Host '  You can delete the downloaded zip and extracted folder now.'
        Write-Host '  Starting it now - click Yes when Windows asks for permission.'
        Write-Host ''
        Start-Process $PsExe $appArgs
    } catch {
        $failedAr = [regex]::Unescape('\u0641\u0634\u0644 \u0627\u0644\u062a\u062b\u0628\u064a\u062a:')   # "Installation failed:" in Arabic
        [void][Windows.MessageBox]::Show(
            "Installation failed:`n$($_.Exception.Message)`n`n$failedAr`n$($_.Exception.Message)",
            $AppName, 'OK', 'Error')
        if ($PSCommandPath) { exit 1 }   # under "irm | iex", exit would close the user's window
    }
}
