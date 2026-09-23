# =====================================================================
#  uninstall.ps1 - removes RL ME Blocker: its firewall rules, shortcuts,
#  Settings > Apps entry and installed files.
#  Runs as the user; only the firewall part is done as Administrator.
# =====================================================================

param([switch]$Elevated)

$AppName = 'RL ME Blocker'
$Group   = 'RL-Block-ME'

# ---- Admin part: close the app and delete the firewall rules -----------
if ($Elevated) {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -like '*RL-ME-Blocker.ps1*' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    try {
        Get-NetFirewallRule -Group $Group -PolicyStore PersistentStore -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction Stop
        exit 0
    } catch { exit 1 }
}

Add-Type -AssemblyName PresentationFramework
function Show-Message([string]$en, [string]$ar, [string]$icon) {
    [void][Windows.MessageBox]::Show("$en`n`n$ar", $AppName, 'OK', $icon)
}

try {
    $p = Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Elevated" `
             -Verb RunAs -Wait -PassThru
} catch {
    Show-Message 'Uninstall cancelled. Administrator permission is needed to remove the firewall rules.' `
                 'تم إلغاء الإزالة. يلزم إذن المسؤول لحذف قواعد الجدار الناري.' 'Warning'
    exit 1
}
if ($p.ExitCode -ne 0) {
    Show-Message "Couldn't remove the firewall rules. Delete the rules named 'RL-Block-ME' in Windows Defender Firewall, then try again." `
                 "تعذّر حذف قواعد الجدار الناري. احذف القواعد باسم 'RL-Block-ME' من جدار حماية Windows Defender ثم حاول مرة أخرى." 'Error'
    exit 1
}

# ---- User part: shortcuts, Apps entry, files ---------------------------
$InstallDir = Join-Path $env:LOCALAPPDATA 'RL-ME-Blocker'
$wsh = New-Object -ComObject WScript.Shell
foreach ($dir in [Environment]::GetFolderPath('Desktop'), [Environment]::GetFolderPath('Programs')) {
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.lnk -ErrorAction SilentlyContinue) {
        try {
            if ($wsh.CreateShortcut($f.FullName).Arguments -like "*$InstallDir\RL-ME-Blocker.ps1*") {
                Remove-Item -LiteralPath $f.FullName -Force
            }
        } catch { }
    }
}
Remove-Item -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\RL-ME-Blocker' -Recurse -Force -ErrorAction SilentlyContinue
Set-Location $env:TEMP   # this script may live in the folder being deleted
Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

Show-Message "$AppName was removed. Middle East servers are no longer blocked." `
             'تمت إزالة البرنامج. سيرفرات الشرق الأوسط لم تعد محظورة.' 'Information'
