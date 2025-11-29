param(
    [string]$Root = 'D:\A11',
    [string]$ShortcutName = 'A11-Local.lnk',
    [string]$TargetScript = 'start_a11_local.ps1',
    [string]$IconPath = '',
    [ValidateSet('Normal','Minimized','Maximized')][string]$WindowStyle = 'Minimized'
)

# Resolve default icon if not provided
if (-not $IconPath -or $IconPath -eq '') {
    $defaultIcon = Join-Path $Root 'apps\web\public\favicon.ico'
    if (Test-Path $defaultIcon) { $IconPath = $defaultIcon }
}

$Desktop = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = Join-Path $Desktop $ShortcutName

if (Test-Path $ShortcutPath) { Remove-Item $ShortcutPath -Force }

$Target = Join-Path $env:WinDir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$ScriptFull = Join-Path $Root $TargetScript
$Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptFull`""

$WshShell = New-Object -ComObject WScript.Shell
$Shortcut = $WshShell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $Target
$Shortcut.Arguments = $Arguments
$Shortcut.WorkingDirectory = $Root

switch ($WindowStyle) {
    'Normal'    { $Shortcut.WindowStyle = 1 }
    'Minimized' { $Shortcut.WindowStyle = 7 }
    'Maximized' { $Shortcut.WindowStyle = 3 }
}

if ($IconPath -and (Test-Path $IconPath)) {
    $Shortcut.IconLocation = "$IconPath,0"
}

$Shortcut.Save()
Write-Host "Created shortcut: $ShortcutPath (icon: $IconPath)"